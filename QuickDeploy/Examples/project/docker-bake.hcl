# <PROJECT> = the project name used for image tags, <PATH/TO/PROJECT/FILES> = the project's source checkout
group "default" {
  targets = ["<PROJECT>_frontend", "<PROJECT>_backend"]
}

target "node_assets" {
  dockerfile = "<PATH/TO/PROJECT/FILES>/docker/common/assets/node.Dockerfile"
  output = [{ type = "cacheonly" }]
  tags = ["<PROJECT>:node-assets"]
}

target "composer_assets" {
  dockerfile = "<PATH/TO/PROJECT/FILES>/docker/common/assets/php.Dockerfile"
  output = [{ type = "cacheonly" }]
  tags = ["<PROJECT>:php-assets"]
}

target "<PROJECT>_frontend" {
  dockerfile = "<PATH/TO/PROJECT/FILES>/docker/production/nginx/Dockerfile"
  contexts = {
    node-assets = "target:node_assets"
  }
  tags = ["<PROJECT>:frontend"]
}

target "<PROJECT>_backend" {
  dockerfile = "<PATH/TO/PROJECT/FILES>/docker/common/php-fpm/Dockerfile"
  contexts = {
    php-assets = "target:composer_assets"
    node-assets = "target:node_assets"
  }
  tags = ["<PROJECT>:backend"]
}
