/**
 * Copyright 2022 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**********************************************************
  Service Agent Permissions to KMS keys and Pub/Sub topics
 **********************************************************/
resource "google_project_service_identity" "secretmanager_identity" {
  count = length(var.add_kms_permissions) > 0 || length(var.add_pubsub_permissions) > 0 ? 1 : 0

  provider = google-beta
  project  = var.project_id
  service  = "secretmanager.googleapis.com"
}

resource "google_kms_crypto_key_iam_member" "sm_sa_encrypter_decrypter" {
  count = length(var.add_kms_permissions)

  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_project_service_identity.secretmanager_identity[0].email}"
  crypto_key_id = var.add_kms_permissions[count.index]
}

resource "google_pubsub_topic_iam_member" "sm_sa_publisher" {
  count = length(var.add_pubsub_permissions)

  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_project_service_identity.secretmanager_identity[0].email}"
  topic  = var.add_pubsub_permissions[count.index]
}

/**********************************************************
  Secret Manager Secret and Version
 **********************************************************/

module "secret" {
  for_each = { for secret in var.secrets : secret.name => secret }

  source = "./modules/simple-secret"

  project_id               = var.project_id
  name                     = each.value.name
  secret_data              = each.value.secret_data
  labels                   = lookup(var.labels, each.key, {})
  topics                   = [for topic in lookup(var.topics, each.key, []) : topic.name]
  user_managed_replication = lookup(var.user_managed_replication, each.key, [])
  automatic_replication    = try(var.automatic_replication[each.key], {})

  depends_on = [
    google_kms_crypto_key_iam_member.sm_sa_encrypter_decrypter,
    google_pubsub_topic_iam_member.sm_sa_publisher
  ]
}

/**********************************************************
  IAM Permissions to the Secret
 **********************************************************/

module "secret_manager_iam" {
  count = length(var.secret_accessors_list) > 0 ? 1 : 0

  source  = "terraform-google-modules/iam/google//modules/secret_manager_iam"
  version = "~> 7.7"

  project = var.project_id
  secrets = [for secret in module.secret : secret.id]
  mode    = "additive"

  bindings = {
    "roles/secretmanager.secretAccessor" = var.secret_accessors_list
  }
}
