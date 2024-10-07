terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.48.0"
    }
  }
  required_version = ">= 1.0.0"
}

provider "openstack" {}

locals {
  control_plane_ip = openstack_compute_instance_v2.okd_control_plane[0].access_ip_v4
  worker_ips       = openstack_compute_instance_v2.okd_worker[*].access_ip_v4
}

resource "openstack_networking_network_v2" "okd_network" {
  name           = "okd-network"
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "okd_subnet" {
  name            = "okd-subnet"
  network_id      = openstack_networking_network_v2.okd_network.id
  cidr            = "192.168.1.0/24"
  ip_version      = 4
  dns_nameservers = ["8.8.8.8", "8.8.4.4"]
}

resource "openstack_networking_router_v2" "okd_router" {
  name                = "okd-router"
  admin_state_up      = true
  external_network_id = var.external_network_id
}

resource "openstack_networking_router_interface_v2" "okd_router_interface" {
  router_id = openstack_networking_router_v2.okd_router.id
  subnet_id = openstack_networking_subnet_v2.okd_subnet.id
}

resource "openstack_networking_secgroup_v2" "okd_secgroup" {
  name        = "okd-secgroup"
  description = "Security group for OKD cluster"
}

resource "openstack_networking_secgroup_rule_v2" "okd_secgroup_rule_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.okd_secgroup.id
}

resource "openstack_networking_secgroup_rule_v2" "okd_secgroup_rule_k8s_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.okd_secgroup.id
}

resource "openstack_networking_secgroup_rule_v2" "okd_secgroup_rule_rke2_server" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 9345
  port_range_max    = 9345
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.okd_secgroup.id
}

resource "openstack_compute_instance_v2" "okd_control_plane" {
  count           = 1
  name            = "okd-control-plane-${count.index + 1}"
  image_id        = var.rhcos_image
  flavor_name     = var.control_plane_flavor
  key_pair        = var.key_pair_name
  security_groups = [openstack_networking_secgroup_v2.okd_secgroup.name]

  block_device {
    uuid                  = var.rhcos_image
    source_type           = "image"
    destination_type      = "volume"
    boot_index            = 0
    delete_on_termination = true
    volume_size           = 20
  }

  network {
    uuid = openstack_networking_network_v2.okd_network.id
  }
}

resource "openstack_compute_instance_v2" "okd_worker" {
  count           = 1
  name            = "okd-worker-${count.index + 1}"
  image_id        = var.rhcos_image
  flavor_name     = var.worker_flavor
  key_pair        = var.key_pair_name
  security_groups = [openstack_networking_secgroup_v2.okd_secgroup.name]

  block_device {
    uuid                  = var.rhcos_image
    source_type           = "image"
    destination_type      = "volume"
    boot_index            = 0
    delete_on_termination = true
    volume_size           = 20
  }

  network {
    uuid = openstack_networking_network_v2.okd_network.id
  }
}

resource "openstack_networking_floatingip_v2" "control_plane_fip" {
  pool = var.floating_ip_pool
}

resource "openstack_compute_floatingip_associate_v2" "control_plane_fip_associate" {
  floating_ip = openstack_networking_floatingip_v2.control_plane_fip.address
  instance_id = openstack_compute_instance_v2.okd_control_plane[0].id
}

resource "openstack_networking_floatingip_v2" "worker_fip" {
  pool = var.floating_ip_pool
}

resource "openstack_compute_floatingip_associate_v2" "worker_fip_associate" {
  floating_ip = openstack_networking_floatingip_v2.worker_fip.address
  instance_id = openstack_compute_instance_v2.okd_worker[0].id
}

resource "openstack_lb_loadbalancer_v2" "control_plane_lb" {
  name          = "control-plane-lb"
  vip_subnet_id = openstack_networking_subnet_v2.okd_subnet.id
}

resource "openstack_lb_listener_v2" "control_plane_listener" {
  name            = "control-plane-listener"
  protocol        = "TCP"
  protocol_port   = 6443
  loadbalancer_id = openstack_lb_loadbalancer_v2.control_plane_lb.id
}

resource "openstack_lb_pool_v2" "control_plane_pool" {
  name        = "control-plane-pool"
  protocol    = "TCP"
  lb_method   = "ROUND_ROBIN"
  listener_id = openstack_lb_listener_v2.control_plane_listener.id
}

resource "openstack_lb_member_v2" "control_plane_member" {
  pool_id       = openstack_lb_pool_v2.control_plane_pool.id
  address       = openstack_compute_instance_v2.okd_control_plane[0].access_ip_v4
  protocol_port = 6443
}

resource "openstack_networking_floatingip_v2" "lb_fip" {
  pool = var.floating_ip_pool
}

resource "openstack_networking_floatingip_associate_v2" "lb_fip_associate" {
  floating_ip = openstack_networking_floatingip_v2.lb_fip.address
  port_id     = openstack_lb_loadbalancer_v2.control_plane_lb.vip_port_id
}

resource "null_resource" "control_plane_setup" {
  connection {
    type        = "ssh"
    user        = "core"
    host        = openstack_networking_floatingip_v2.control_plane_fip.address
    private_key = file("/Users/munnaali/Downloads/id_rsa")
  }

  provisioner "remote-exec" {
    inline = [
      "curl -sfL https://get.rke2.io | sudo sh -",
      "sudo systemctl enable rke2-server.service",
      "sudo systemctl start rke2-server.service",
      "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes || true",
    ]
  }

  depends_on = [
    openstack_compute_floatingip_associate_v2.control_plane_fip_associate,
  ]
}

resource "null_resource" "get_node_token" {
  depends_on = [null_resource.control_plane_setup]

  connection {
    type        = "ssh"
    user        = "core"
    host        = openstack_networking_floatingip_v2.control_plane_fip.address
    private_key = file("/Users/munnaali/Downloads/id_rsa")
  }

  provisioner "local-exec" {
    command = "ssh -o StrictHostKeyChecking=no -i /Users/munnaali/Downloads/id_rsa core@${openstack_networking_floatingip_v2.control_plane_fip.address} 'sudo cat /var/lib/rancher/rke2/server/node-token' > node-token.txt"
  }
}

resource "null_resource" "worker_setup" {
  depends_on = [null_resource.get_node_token]

  connection {
    type        = "ssh"
    user        = "core"
    host        = openstack_networking_floatingip_v2.worker_fip.address
    private_key = file("/Users/munnaali/Downloads/id_rsa")
  }

  provisioner "file" {
    source      = "node-token.txt"
    destination = "/tmp/node-token.txt"
  }

  provisioner "remote-exec" {
    inline = [
      "curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE='agent' sudo sh -",
      "sudo mkdir -p /etc/rancher/rke2",
      "echo \"server: https://${openstack_compute_instance_v2.okd_control_plane[0].access_ip_v4}:9345\" | sudo tee /etc/rancher/rke2/config.yaml",
      "echo \"token: $(cat /tmp/node-token.txt)\" | sudo tee -a /etc/rancher/rke2/config.yaml",
      "sudo systemctl enable rke2-agent.service",
      "sudo systemctl start rke2-agent.service",
    ]
  }
}

resource "null_resource" "get_kubeconfig" {
  depends_on = [null_resource.worker_setup, openstack_networking_floatingip_associate_v2.lb_fip_associate]

  connection {
    type        = "ssh"
    user        = "core"
    host        = openstack_networking_floatingip_v2.control_plane_fip.address
    private_key = file("/Users/munnaali/Downloads/id_rsa")
  }

  provisioner "local-exec" {
    command = "ssh -o StrictHostKeyChecking=no -i /Users/munnaali/Downloads/id_rsa core@${openstack_networking_floatingip_v2.control_plane_fip.address} 'sudo cat /etc/rancher/rke2/rke2.yaml' > kubeconfig.yaml"
  }

  provisioner "local-exec" {
    command = "sed -i '' 's/127.0.0.1/${openstack_networking_floatingip_v2.lb_fip.address}/g' kubeconfig.yaml"
  }
}

output "control_plane_floating_ip" {
  value = openstack_networking_floatingip_v2.control_plane_fip.address
}

output "worker_floating_ip" {
  value = openstack_networking_floatingip_v2.worker_fip.address
}

output "control_plane_private_ip" {
  value = openstack_compute_instance_v2.okd_control_plane[0].access_ip_v4
}

output "worker_private_ip" {
  value = openstack_compute_instance_v2.okd_worker[0].access_ip_v4
}

output "load_balancer_ip" {
  value = openstack_lb_loadbalancer_v2.control_plane_lb.vip_address
}

output "kubeconfig" {
  value = "kubeconfig.yaml file has been created in the current directory. Use 'export KUBECONFIG=./kubeconfig.yaml' to start using kubectl."
}

output "load_balancer_floating_ip" {
  value = openstack_networking_floatingip_v2.lb_fip.address
}