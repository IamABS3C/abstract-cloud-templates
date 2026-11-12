# Offline checks: no Azure login, no resources. Run: terraform init -backend=false && terraform test
mock_provider "azurerm" {}

variables {
  resource_group_name   = "abstract-sentinel"
  nativeVendors         = ["okta", "csl-cef"]
  enabledAnalyticsRules = ["finding"]
  enableAutomationRules = true
}

run "parameters_carry_the_choices" {
  command = plan

  assert {
    condition     = jsondecode(azurerm_resource_group_template_deployment.solution.parameters_content).nativeVendors.value == ["okta", "csl-cef"]
    error_message = "parameters_content must carry nativeVendors"
  }

  assert {
    condition     = jsondecode(azurerm_resource_group_template_deployment.solution.parameters_content).enabledAnalyticsRules.value == ["finding"]
    error_message = "parameters_content must carry enabledAnalyticsRules"
  }

  assert {
    condition     = jsondecode(azurerm_resource_group_template_deployment.solution.parameters_content).enableAutomationRules.value == true
    error_message = "parameters_content must carry enableAutomationRules"
  }

  assert {
    condition     = !contains(keys(jsondecode(azurerm_resource_group_template_deployment.solution.parameters_content)), "principalId")
    error_message = "an empty principalId must not be sent, so the template keeps its own default"
  }
}

run "deploys_the_solution_template" {
  command = plan

  assert {
    condition     = jsondecode(azurerm_resource_group_template_deployment.solution.template_content).outputs.abstractDestination.type == "object"
    error_message = "template_content must be the solution's azuredeploy.json"
  }
}

run "extra_parameters_override" {
  command = plan

  variables {
    principalId      = "00000000-0000-0000-0000-000000000001"
    extra_parameters = { enableAsim = true, enableAutomationRules = false }
  }

  assert {
    condition     = jsondecode(azurerm_resource_group_template_deployment.solution.parameters_content).enableAsim.value == true
    error_message = "extra_parameters must reach the template"
  }

  assert {
    condition     = jsondecode(azurerm_resource_group_template_deployment.solution.parameters_content).enableAutomationRules.value == false
    error_message = "extra_parameters must override the named variables"
  }

  assert {
    condition     = jsondecode(azurerm_resource_group_template_deployment.solution.parameters_content).principalId.value == "00000000-0000-0000-0000-000000000001"
    error_message = "principalId must reach the template"
  }
}

run "extra_parameters_mix_types" {
  command = plan

  variables {
    extra_parameters = { enableAsim = true, asimSchemas = ["Authentication", "NetworkSession"], lakeRetentionDays = 180 }
  }

  assert {
    condition     = jsondecode(azurerm_resource_group_template_deployment.solution.parameters_content).asimSchemas.value == ["Authentication", "NetworkSession"]
    error_message = "a list must reach the template next to a bool"
  }

  assert {
    condition     = jsondecode(azurerm_resource_group_template_deployment.solution.parameters_content).enableAsim.value == true
    error_message = "a bool must reach the template next to a list"
  }

  assert {
    condition     = jsondecode(azurerm_resource_group_template_deployment.solution.parameters_content).lakeRetentionDays.value == 180
    error_message = "a number must reach the template"
  }
}

run "extra_parameters_must_be_an_object" {
  command = plan

  variables {
    extra_parameters = ["enableAsim"]
  }

  expect_failures = [var.extra_parameters]
}

run "api_key_is_sent_only_when_given" {
  command = plan

  assert {
    condition     = !contains(keys(jsondecode(azurerm_resource_group_template_deployment.solution.parameters_content)), "abstractApiKey")
    error_message = "an empty abstractApiKey must not be sent, so the template keeps its own default"
  }

  assert {
    condition     = jsondecode(azurerm_resource_group_template_deployment.solution.parameters_content).keyVaultMode.value == "None"
    error_message = "keyVaultMode must default to None, which stores nothing"
  }
}

run "api_key_is_passed_with_create" {
  command = plan

  variables {
    keyVaultMode   = "Create"
    abstractApiKey = "test-key-not-real"
  }

  assert {
    condition     = jsondecode(nonsensitive(azurerm_resource_group_template_deployment.solution.parameters_content)).abstractApiKey.value == "test-key-not-real"
    error_message = "abstractApiKey must reach the template with keyVaultMode Create"
  }
}
