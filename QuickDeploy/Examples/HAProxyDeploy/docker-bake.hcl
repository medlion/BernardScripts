group "default" {
  targets = ["haproxy"]
}

# Directory holding the mkcert CA (rootCA.pem + rootCA-key.pem), i.e. `mkcert -CAROOT`.
# Override per machine with: CAROOT=$(mkcert -CAROOT) docker buildx bake
variable "CAROOT" {
  default = "<PATH/TO/MKCERT/CAROOT>"
}

# Hostnames on the certificate (space-separated). Add new apps here and rebuild.
variable "CERT_NAMES" {
  default = "localhost <APP_HOST_1> <APP_HOST_2>"
}

target "haproxy" {
  dockerfile = "Dockerfile"
  tags = ["haproxy-dataplane:latest"]
  args = {
    CERT_NAMES = CERT_NAMES
  }
  contexts = {
    caroot = CAROOT
  }
}
