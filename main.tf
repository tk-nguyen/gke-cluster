terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.20.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.5.1"
    }
  }
}

provider "google" {
  project = var.project_id
  zone    = "asia-southeast1-a"
}

# Configuration so helm provider can connect to the created cluster
provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.gke_cluster.endpoint}"
    cluster_ca_certificate = base64decode(google_container_cluster.gke_cluster.master_auth[0].cluster_ca_certificate)
    token                  = data.google_client_config.gcp_client_config.access_token
  }
}

# Get the current configuration of calling user
data "google_client_config" "gcp_client_config" {}

resource "google_service_account" "gke_node_service_account" {
  account_id   = "gke-node-service-account"
  display_name = "GKE Node Service Account"
}

resource "google_container_cluster" "gke_cluster" {
  name = var.gke_cluster_name
  # Seperately managed node pool
  initial_node_count       = 1
  remove_default_node_pool = true
}

resource "google_container_node_pool" "gke_node_pool" {
  name               = "${var.gke_cluster_name}-node-pool"
  cluster            = google_container_cluster.gke_cluster.id
  initial_node_count = var.gke_node_count
  node_config {
    machine_type    = var.gke_node_pool_machine_type
    service_account = google_service_account.gke_node_service_account.email
    disk_size_gb    = 15
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

# We install components by using helm provider
resource "helm_release" "nginx-ingress" {
  name             = "ingress-nginx"
  chart            = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
}

resource "helm_release" "grafana" {
  name             = "grafana"
  chart            = "grafana"
  repository       = "https://grafana.github.io/helm-charts"
  namespace        = "grafana"
  create_namespace = true
  set {
    name  = "ingress.enabled"
    value = "true"
  }
  set {
    name  = "ingress.ingressClassName"
    value = "nginx"
  }
  set {
    name  = "ingress.hosts"
    value = "{grafana.demo.cluster}"
  }
}
