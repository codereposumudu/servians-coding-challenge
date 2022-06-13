data "aws_instance" "bastion_host" {
  instance_tags = {
    Name = "${var.env_prefix}-bastion"
  }

  depends_on = [
    var.eks_cluster_name,
    var.eks_fargate_profile_id,
    var.eks_fargate_role_arn
  ]
}
########################################################################################
#Null provitioners for post configurations
##########################################################################################

resource "null_resource" "local_before" {

  provisioner "local-exec" {
    command = "echo \"export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID\" > credentials.txt"
  }

  provisioner "local-exec" {
    command = "echo \"export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY\" >> credentials.txt"
  }

  provisioner "local-exec" {
    command = "echo \"export AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION\" >> credentials.txt"
  }

  depends_on = [
    data.aws_instance.bastion_host
  ]
}

resource "null_resource" "bastion" {
  
  triggers = {
    version = timestamp()
  }
  

  connection {
    type        = "ssh"
    user        = "ec2-user"
    host        = data.aws_instance.bastion_host.public_ip
    port        = var.bastion_allowed_port
    private_key = var.bastion_private_key
    timeout     = "10s"
  }

  provisioner "file" {
    source      = "credentials.txt"
    destination = "credentials.txt"
  }

  # Copy helm chart values file for ALB ingress controller
  provisioner "file" {
    source      = "modules/post-config/conf/alb_controller_helm_values.yaml"
    destination = "alb_controller_helm_values.yaml"
  }
  
  provisioner "file" {
    content = templatefile("${path.module}/post-config.sh.tpl", {
      vpc_id                              = var.vpc_id,
      domain_name                         = var.domain_name,
      cluster_name                        = var.eks_cluster_name,
      eks_fargate_role_arn                = var.eks_fargate_role_arn,
      eks_node_role_arn                   = var.eks_node_role_arn,
      eks_external_dns_role_arn           = var.eks_external_dns_role_arn,
      eks_lb_controller_role_arn          = var.eks_lb_controller_role_arn,
      eks_k8s_masters_role_arn            = var.eks_k8s_masters_role_arn,
      eks_k8s_readonly_role_arn           = var.eks_k8s_readonly_role_arn,
      eks_arn_user_list_with_masters_user = var.eks_arn_user_list_with_masters_user
      eks_alb_ing_ssl_cert_arn            = var.eks_alb_ing_ssl_cert_arn
      app_backend_db_host                 = var.app_backend_db_host
      app_backend_db_port                 = var.app_backend_db_port
      app_backend_db_user                 = var.app_backend_db_user
      app_backend_db_password             = var.app_backend_db_password
    })
    destination = "post-config.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sh post-config.sh"
      # ,
      # "rm post-config.sh"
    ]
  }

  depends_on = [
    null_resource.local_before
  ]
}

resource "null_resource" "local_after" {
  /*
  triggers = {
    version = timestamp()
  }
  */

  provisioner "local-exec" {
    command = "rm credentials.txt"
  }

  depends_on = [
    null_resource.bastion
  ]
}
