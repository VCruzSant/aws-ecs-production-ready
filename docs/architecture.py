from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import ECR, Fargate
from diagrams.aws.database import RDS
from diagrams.aws.management import Cloudwatch
from diagrams.aws.network import ALB, InternetGateway, NATGateway
from diagrams.aws.security import SecretsManager
from diagrams.aws.storage import S3
from diagrams.onprem.client import Users

graph_attr = {"pad": "0.4", "nodesep": "0.7", "ranksep": "1.0", "fontsize": "20", "dpi": "150"}
cluster_attr = {"fontsize": "16"}

with Diagram(
    "",
    filename="architecture",
    outformat="png",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
):
    users = Users("Users")

    with Cluster("AWS region", graph_attr=cluster_attr):
        with Cluster("VPC, 2 Availability Zones", graph_attr=cluster_attr):
            with Cluster("Public subnets", graph_attr=cluster_attr):
                alb = ALB("Application\nLoad Balancer")
                nat = NATGateway("NAT Gateway")
                igw = InternetGateway("Internet\nGateway")

            with Cluster("Private subnets", graph_attr=cluster_attr):
                tasks = Fargate("ECS Fargate\ntasks")
                db = RDS("RDS PostgreSQL\nTLS verify-full")

        with Cluster("Regional services", graph_attr=cluster_attr):
            ecr = ECR("ECR")
            secrets = SecretsManager("Secrets Manager\nDB password")
            logs = Cloudwatch("CloudWatch Logs\napp + flow logs")
            alb_logs = S3("ALB access logs")

    with Cluster("Bootstrap, kept after destroy", graph_attr=cluster_attr):
        state = S3("Terraform state")
        budget = Cloudwatch("AWS Budget")

    users >> igw >> alb >> tasks >> db
    tasks >> Edge(style="dashed", label="via NAT") >> nat
    nat >> Edge(style="dashed") >> ecr
    ecr - Edge(style="invis") - secrets - Edge(style="invis") - logs - Edge(style="invis") - alb_logs
    alb >> Edge(style="dotted") >> alb_logs
    state - Edge(style="invis") - budget
