# Tests for the input guards.
#
# These exist because the guards encode AWS semantics that are easy to get subtly
# wrong, and a guard nobody exercises is a guard you hope works. The overlap rule in
# particular is narrower than "prefixes must not collide" - AWS permits overlapping
# prefixes when the suffixes disambiguate them - so both the accept and the reject
# case need pinning.
#
# The provider is mocked, so this runs with no AWS credentials and no network:
#   tofu test        (or: terraform test)

# The generated mock for aws_iam_policy_document returns a placeholder string for
# .json, which aws_iam_role then rejects as invalid policy JSON. Give it something
# well-formed - these tests are about the input guards, not policy content.
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

mock_provider "random" {}

variables {
  bucket_name             = "example-security-logs"
  abstract_aws_account_id = "000000000000"
  routing_mode            = "direct"
}

# ── the overlap guard ───────────────────────────────────────────────────────

run "rejects_nested_prefixes_when_suffixes_also_overlap" {
  command = plan

  variables {
    sources = {
      logs   = { prefix = "logs/" }
      nested = { prefix = "logs/cloudtrail/" }
    }
  }

  # Both sources have an empty suffix, which matches everything, so the prefixes
  # genuinely collide. In direct mode S3 rejects the whole notification
  # configuration; in sns/eventbridge mode the object is delivered twice.
  expect_failures = [var.sources]
}

run "allows_shared_prefix_when_suffixes_disambiguate" {
  command = plan

  variables {
    sources = {
      json_logs    = { prefix = "logs/", suffix = ".json.gz" }
      parquet_logs = { prefix = "logs/", suffix = ".parquet" }
    }
  }

  # AWS's own documented example is two rules on one prefix separated by suffix.
  # A guard that rejected this would be over-strict and would block a legitimate
  # layout.
  assert {
    condition     = length(var.sources) == 2
    error_message = "Shared prefix with non-overlapping suffixes must be permitted."
  }
}

run "rejects_shared_prefix_when_one_suffix_is_empty" {
  command = plan

  variables {
    sources = {
      everything = { prefix = "logs/" }
      just_gz    = { prefix = "logs/", suffix = ".gz" }
    }
  }

  # An empty suffix matches every object, so it always overlaps.
  expect_failures = [var.sources]
}

run "allows_disjoint_prefixes" {
  command = plan

  variables {
    sources = {
      cloudtrail = { prefix = "cloudtrail/" }
      guardduty  = { prefix = "guardduty/" }
    }
  }

  assert {
    condition     = length(var.sources) == 2
    error_message = "Disjoint prefixes are the ordinary case and must plan cleanly."
  }
}

# ── the remaining input guards ──────────────────────────────────────────────

run "rejects_empty_prefix" {
  command = plan

  variables {
    sources = {
      everything = { prefix = "" }
    }
  }

  # An empty prefix silently captures the whole bucket and collides with every
  # other source.
  expect_failures = [var.sources]
}

run "rejects_csv_dataformat" {
  command = plan

  variables {
    sources = {
      umbrella = { prefix = "dns/", dataformat = "csv" }
    }
  }

  # There is no CSV decoder. Accepting it here would defer the failure to the
  # source decoder at runtime, where it surfaces as unparseable objects rather
  # than a config error.
  expect_failures = [var.sources]
}

run "rejects_malformed_abstract_account_id" {
  command = plan

  variables {
    abstract_aws_account_id = "not-an-account"
    sources = {
      cloudtrail = { prefix = "cloudtrail/" }
    }
  }

  expect_failures = [var.abstract_aws_account_id]
}

run "rejects_unknown_routing_mode" {
  command = plan

  variables {
    routing_mode = "carrier-pigeon"
    sources = {
      cloudtrail = { prefix = "cloudtrail/" }
    }
  }

  expect_failures = [var.routing_mode]
}
