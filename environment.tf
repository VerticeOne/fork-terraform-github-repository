locals {
  environment_variables = merge([
    for env_name, env_config in var.environments : {
      for var_name, var_value in env_config.env_variables : "${env_name}_${lower(var_name)}" => {
        env_name  = env_name
        var_name  = var_name
        var_value = var_value
      }
    }
  ]...)
  environment_secrets = merge([
    for env_name, env_config in var.environments : {
      for secret_name, secret_value in env_config.env_secrets : "${env_name}_${lower(secret_name)}" => {
        env_name  = env_name
        var_name  = secret_name
        var_value = secret_value
      }
    }
  ]...)
  all_environment_deployment_policies = merge(
    # Branch deployment policies
    merge([
      for env_name, env_config in var.environments : {
        for policy_index, policy_pattern in env_config.branch_deployment_policies : "${env_name}_branch_policy_${policy_index}" => {
          env_name       = env_name
          branch_pattern = policy_pattern
        }
      } if env_config.deployment_branch_policy.custom_branch_policies
    ]...),
    # Tag deployment policies
    merge([
      for env_name, env_config in var.environments : {
        for policy_index, policy_pattern in env_config.tag_deployment_policies : "${env_name}_tag_policy_${policy_index}" => {
          env_name    = env_name
          tag_pattern = policy_pattern
        }
      } if env_config.deployment_branch_policy.custom_branch_policies
    ]...)
  )
}

resource "github_repository_environment" "repository_environment" {
  for_each            = var.environments
  environment         = each.key
  repository          = github_repository.repository.name
  wait_timer          = each.value.wait_timer
  can_admins_bypass   = each.value.admin_bypass
  prevent_self_review = each.value.prevent_self_review

  dynamic "reviewers" {
    for_each = (
      length(each.value.reviewers.users) > 0 ||
      length(each.value.reviewers.teams) > 0
    ) ? [1] : []

    content {
      users = each.value.reviewers.users
      teams = each.value.reviewers.teams
    }
  }

  dynamic "deployment_branch_policy" {
    for_each = (
      each.value.deployment_branch_policy.protected_branches ||
      each.value.deployment_branch_policy.custom_branch_policies
    ) ? [1] : []

    content {
      protected_branches     = each.value.deployment_branch_policy.protected_branches
      custom_branch_policies = each.value.deployment_branch_policy.custom_branch_policies
    }
  }
}

resource "github_actions_environment_variable" "environment_variables" {
  for_each = local.environment_variables

  environment   = github_repository_environment.repository_environment[each.value.env_name].environment
  repository    = github_repository.repository.name
  variable_name = each.value.var_name
  value         = each.value.var_value
}

resource "github_actions_environment_secret" "environment_secrets" {
  for_each        = local.environment_secrets
  environment     = github_repository_environment.repository_environment[each.value.env_name].environment
  repository      = github_repository.repository.name
  secret_name     = each.value.var_name
  plaintext_value = each.value.var_value
}


resource "github_repository_environment_deployment_policy" "environment_deployment_policy" {
  for_each       = local.all_environment_deployment_policies
  environment    = github_repository_environment.repository_environment[each.value.env_name].environment
  repository     = github_repository.repository.name
  branch_pattern = lookup(each.value, "branch_pattern", null)
  tag_pattern    = lookup(each.value, "tag_pattern", null)
}