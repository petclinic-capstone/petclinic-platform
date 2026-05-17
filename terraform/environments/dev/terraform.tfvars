github_org      = "petclinic-capstone"
github_repo     = ["petclinic-capstone/spring-petclinic-microservices"]
github_tf_repos = ["petclinic-capstone/petclinic-platform"]
github_branch   = "master"

# Route53 hosted zone — must already exist (delegated from Cloudflare)
# Terraform looks this up as a data source; it does NOT create or destroy it.
domain_name = "demo.lulamistack.co"
