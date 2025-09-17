
# See https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acmpca_certificate_authority_certificate


# https://chrisguitarguy.com/2023/03/19/create-your-own-certificate-authority-with-terraform/
# resource "aws_kms_key" "ca" {
#   description = "${var.name} certificate authority"
# }

# resource "aws_kms_alias" "ca" {
#   name          = "alias/${var.name}-ca"
#   target_key_id = aws_kms_key.ca.key_id
# }

# resource "aws_ssm_parameter" "ca-private-key" {
#   name   = "/${lower(var.name)}/ca_private_key"
#   type   = "SecureString"
#   key_id = aws_kms_key.ca.id
#   value  = "BRAVE"

#   lifecycle {
#     ignore_changes = [value]
#   }
# }

# resource "aws_ssm_parameter" "client-private-key" {
#   name   = "/${lower(var.name)}/client_private_key"
#   type   = "SecureString"
#   key_id = aws_kms_key.ca.id
#   value  = "BRAVE"

#   lifecycle {
#     ignore_changes = [value]
#   }
# }

# locals {
#   ten_years   = 87600
#   five_years  = 43830
#   ninety_days = 2160
# }

# resource "tls_self_signed_cert" "ca" {
#   private_key_pem   = aws_ssm_parameter.ca-private-key.value
#   is_ca_certificate = true

#   subject {
#     common_name = "braveresearchcollaborative.org"
#   }

#   validity_period_hours = local.ten_years
#   early_renewal_hours   = local.ninety_days

#   allowed_uses = [
#     "cert_signing",
#     "crl_signing",
#     "code_signing",
#     "server_auth",
#     "client_auth",
#     "digital_signature",
#     "key_encipherment",
#   ]
# }


# resource "aws_acm_certificate" "ca" {
#   private_key      = aws_ssm_parameter.ca-private-key.value
#   certificate_body = tls_self_signed_cert.ca.cert_pem
# }

# resource "local_file" "ca-certificate" {
#   content         = tls_self_signed_cert.ca.cert_pem
#   filename        = "${path.module}/certificates/ca.pem"
#   file_permission = "0666"
# }



# resource "tls_cert_request" "client" {
#   private_key_pem = aws_ssm_parameter.client-private-key.value

#   subject {
#     common_name = "braveresearchcollaborative.org"
#   }
# }

# resource "tls_locally_signed_cert" "client" {
#   cert_request_pem   = tls_cert_request.client.cert_request_pem
#   ca_private_key_pem = aws_ssm_parameter.ca-private-key.value
#   ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

#   validity_period_hours = local.five_years
#   early_renewal_hours   = local.ninety_days

#   allowed_uses = [
#     "client_auth",
#   ]
# }

# resource "local_file" "client-certificate" {
#   content         = tls_locally_signed_cert.client.cert_pem
#   filename        = "${path.module}/certificates/client.pem"
#   file_permission = "0666"
# }
# resource "kubectl_manifest" "certificate" {
#   depends_on = [
#     helm_release.cert-manager
#   ]
#   yaml_body = <<YAML
# apiVersion: cert-manager.io/v1
# kind: Certificate
# metadata:
#   name: argo
# spec:
#   secretName: argo-tls
#   privateKey:
#     rotationPolicy: Always
#   commonName: argo.braveresearchcollaborative.org
#   dnsNames:
#     - argo.braveresearchcollaborative.org
#   usages:
#     - digital signature
#     - key encipherment
#     - server auth
#   issuerRef:
#     name: letsencrypt-staging
#     kind: ClusterIssuer
# YAML
# }

# resource "kubectl_manifest" "argo_workflows_ingress" {
#   yaml_body = <<YAML
#   apiVersion: networking.k8s.io/v1
#   kind: Ingress
#   metadata:
#     annotations:
#       alb.ingress.kubernetes.io/backend-protocol: HTTPS
#       # Use this annotation (which must match a service name) to route traffic to HTTP2 backends.
#       alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
#     name: argo-server
#     namespace: argo-workflows
#   spec:
#     rules:
#     - host: argo.braveresearchcollaborative.org
#       http:
#         paths:
#         - path: /
#           pathType: ImplementationSpecific
#           backend:
#             service:
#               name: argo-workflows-server
#               namespace: argo-workflows
#               port:
#                 number: 2746
# YAML
# }

# resource "aws_iam_policy" "cert-manager-acme-dns01-route53" {
#   name        = "cert-manager-acme-dns01-route53"
#   path        = "/"
#   description = "This policy allows cert-manager to manage ACME DNS01 records in Route53 hosted zones. See https://cert-manager.io/docs/configuration/acme/dns01/route53"

#   # Terraform's "jsonencode" function converts a
#   # Terraform expression result to valid JSON syntax.
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = [
#           "route53:GetChange",
#         ]
#         Effect   = "Allow"
#         Resource = "arn:aws:route53:::change/*"
#       },
#     ],
#     Statement = [
#       {
#         Action = [
#           "route53:ChangeResourceRecordSets",
#           "route53:ListResourceRecordSets"
#         ]
#         Effect   = "Allow"
#         Resource = "arn:aws:route53:::hostedzone/*"
#       }
#     ],
#     Statement = [
#       {
#         Action   = ["route53:ListHostedZonesByName"]
#         Effect   = "Allow"
#         Resource = "*"
#       }
#     ]
#   })
# }

# resource "aws_iam_role" "cert-manager-acme-dns01-route53" {
#   name = "cert-manager-acme-dns01-route53"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRoleWithWebIdentity"
#         Effect = "Allow"
#         Principal = {
#           Federated = "${module.eks.oidc_provider_arn}"
#         }
#         Condition = {
#           StringEquals = {
#             # Compare the OIDC audience claim to ensure it's for this service account
#             "${module.eks.oidc_provider}:sub" = "system:serviceaccount:cert-manager:cert-manager-acme-dns01-route53"
#             # Optional but recommended: Restrict audience claim
#             "${module.eks.oidc_provider}:aud" = "sts.amazonaws.com"
#           }
#         }
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "cert-manager-acme-dns01-route53" {
#   role       = aws_iam_role.cert-manager-acme-dns01-route53.name
#   policy_arn = aws_iam_policy.cert-manager-acme-dns01-route53.arn
# }



# resource "kubernetes_role_v1" "cert-manager-acme-dns01-route53-tokenrequest" {
#   depends_on = [helm_release.cert-manager]
#   metadata {
#     name      = "cert-manager-acme-dns01-route53-tokenrequest"
#     namespace = "cert-manager"
#   }
#   rule {
#     api_groups     = [""]
#     resources      = ["serviceaccounts/token"]
#     resource_names = ["cert-manager-acme-dns01-route53"]
#     verbs          = ["create"]
#   }
# }

# resource "kubernetes_role_binding_v1" "cert-manager" {
#   depends_on = [helm_release.cert-manager]
#   metadata {
#     name      = "cert-manager-acme-dns01-route53-tokenrequest"
#     namespace = "cert-manager"
#   }
#   subject {
#     kind      = "ServiceAccount"
#     name      = "cert-manager"
#     namespace = "cert-manager"
#   }
#   role_ref {
#     api_group = "rbac.authorization.k8s.io"
#     kind      = "Role"
#     name      = "cert-manager-acme-dns01-route53-tokenrequest"
#   }
# }

# resource "kubectl_manifest" "clusterissuer_letsencrypt_staging" {
#   depends_on = [
#     helm_release.cert-manager
#   ]
#   yaml_body = <<YAML
# apiVersion: cert-manager.io/v1
# kind: ClusterIssuer
# metadata:
#   name: letsencrypt-production
# spec:
#   acme:
#     server: https://acme-v02.api.letsencrypt.org/directory
#     email: jrussell9000@gmail.com
#     profile: tlsserver
#     privateKeySecretRef:
#       name: letsencrypt-production
#     solvers:
#     - dns01:
#         route53: {}
# YAML
# }

# resource "kubectl_manifest" "certificate_letsencrypt_staging" {
#   depends_on = [helm_release.cert-manager]
#   yaml_body  = <<YAML
# apiVersion: cert-manager.io/v1
# kind: Certificate
# metadata:
#   name: www
# spec:
#   secretName: www-tls
#   privateKey:
#     rotationPolicy: Always
#   commonName: braveresearchcollaborative.org
#   dnsNames:
#     - braveresearchcollaborative.org
#   usages:
#     - digital signature
#     - key encipherment
#     - server auth
#     - client auth
#   issuerRef:
#     name: letsencrypt-production
#     kind: ClusterIssuer
# YAML
# }
