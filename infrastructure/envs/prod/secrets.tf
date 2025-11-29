# Define the parameters but ignore values (managed by sync-vars.ts / Console)
resource "aws_ssm_parameter" "db_url" {
  name  = "/velox/prod/DATABASE_URL"
  type  = "SecureString"
  value = "CHANGE_ME"

  lifecycle { ignore_changes = [value] }
}
