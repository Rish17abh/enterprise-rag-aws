###############################################################################
# S3 uploads (.pdf / .txt) -> EventBridge -> Step Functions
###############################################################################

# Enable EventBridge notifications on the Phase 1 ingestion bucket
resource "aws_s3_bucket_notification" "documents" {
  bucket      = local.s3_bucket_id
  eventbridge = true
}

resource "aws_cloudwatch_event_rule" "s3_object_created" {
  name        = "${var.project_name}-s3-ingest-objects"
  description = "Start ingestion Step Function on PDF/TXT uploads"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [local.s3_bucket_id]
      }
      object = {
        key = [
          {
            wildcard = "*.pdf"
          },
          {
            wildcard = "*.txt"
          },
          {
            wildcard = "*.PDF"
          },
          {
            wildcard = "*.TXT"
          }
        ]
      }
    }
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "start_ingestion" {
  rule      = aws_cloudwatch_event_rule.s3_object_created.name
  target_id = "StartIngestionStateMachine"
  arn       = aws_sfn_state_machine.ingestion.arn
  role_arn  = aws_iam_role.events_to_sfn.arn

  input_transformer {
    input_paths = {
      bucket = "$.detail.bucket.name"
      key    = "$.detail.object.key"
    }
    input_template = <<EOF
{
  "bucket": <bucket>,
  "key": <key>
}
EOF
  }
}
