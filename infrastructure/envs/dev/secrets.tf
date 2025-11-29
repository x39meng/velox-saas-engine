# Define the parameters but ignore values (managed by sync-vars.ts / Console)
resource "aws_ssm_parameter" "db_url" {
  name  = "/velox/dev/DATABASE_URL"
  type  = "SecureString"
  value = "CHANGE_ME"

  lifecycle { ignore_changes = [value] }
}
