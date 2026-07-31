output "app_instance_profile_name"     { value = aws_iam_instance_profile.app.name }
output "jenkins_instance_profile_name" { value = aws_iam_instance_profile.jenkins.name }
output "app_role_arn"                  { value = aws_iam_role.app.arn }
output "jenkins_role_arn"              { value = aws_iam_role.jenkins.arn }
