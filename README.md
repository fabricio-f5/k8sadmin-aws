# k8sadmin-aws

Provisionamento e configuração de um cluster Kubernetes na AWS usando Terraform, Terragrunt e Ansible — sem SSH, sem bastião, acesso 100% via AWS SSM.

---

## O que este projeto faz

Sobe um cluster Kubernetes de 3 nós (1 control-plane + 2 workers) na AWS do zero:

1. **Infra** — VPC, subnets, Security Groups, IAM roles e instâncias EC2 provisionados via Terraform/Terragrunt
2. **Cluster** — containerd, kubeadm, Flannel CNI e kubectl instalados e configurados via Ansible
3. **Acesso seguro** — todo acesso às instâncias é feito via AWS SSM Session Manager (sem portas abertas, sem chaves SSH expostas)
4. **CI/CD** — GitHub Actions aplica/destroi a infra usando OIDC (sem `AWS_ACCESS_KEY_ID` armazenado)

---

## Arquitetura

```
┌─────────────────────────────────────────────────────────┐
│  AWS  (us-east-1)                                        │
│                                                          │
│  ┌─── VPC 10.0.0.0/16 ──────────────────────────────┐  │
│  │                                                    │  │
│  │  Subnet pública 10.0.1.0/24                        │  │
│  │                                                    │  │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐   │  │
│  │  │  master-1  │  │  worker-1  │  │  worker-2  │   │  │
│  │  │  t3.small  │  │  t3.small  │  │  t3.small  │   │  │
│  │  │ control-   │  │            │  │            │   │  │
│  │  │  plane     │  │            │  │            │   │  │
│  │  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘   │  │
│  │        └───────────────┴───────────────┘           │  │
│  │                  Security Group                     │  │
│  │               (Kubernetes ports)                    │  │
│  └────────────────────────────────────────────────────┘  │
│                           │                              │
│              IAM Role  +  SSM Agent                      │
│                           │                              │
│         ┌─────────────────┘                             │
│         │  SSM Session Manager                          │
│         │  (sem SSH / sem porta 22)                     │
│                                                          │
│  S3 Bucket ── Terraform state (encrypted + versioned)   │
└─────────────────────────────────────────────────────────┘
         │                        │
   GitHub Actions            Ansible (local)
   (OIDC — sem keys)         via SSM connection
```

---

## Stack de tecnologias

| Camada | Tecnologia | Versão |
|---|---|---|
| Infra como código | Terraform + Terragrunt | ~1.10 / 0.67 |
| Cloud | AWS (EC2, VPC, IAM, S3, SSM) | Provider ~5.0 |
| Config management | Ansible | 10.x |
| Container runtime | containerd | distro |
| Orquestrador | Kubernetes (kubeadm) | 1.29 |
| CNI | Flannel | latest |
| CI/CD | GitHub Actions + OIDC | — |
| Acesso remoto | AWS SSM Session Manager | — |

---

## Decisões técnicas relevantes

**SSM em vez de SSH**
Nenhuma porta 22 aberta, nenhuma chave `.pem` distribuída. O acesso às instâncias usa o SSM Agent já instalado via Ansible e a IAM role `AmazonSSMManagedInstanceCore`. Elimina a superfície de ataque do bastião.

**Terragrunt para DRY**
Em vez de duplicar `provider.tf` e `backend.tf` em cada módulo, o `root.hcl` os gera automaticamente. Adicionar um novo ambiente exige criar um único `terragrunt.hcl` referenciando o módulo.

**OIDC no GitHub Actions**
O workflow assume uma IAM role via token OIDC do GitHub. Nenhuma `AWS_SECRET_ACCESS_KEY` armazenada como secret — elimina o risco de vazamento de credenciais estáticas.

**IMDSv2 obrigatório**
Todas as instâncias têm `http_tokens = required`. Impede ataques SSRF que tentam extrair credenciais da metadata API.

**Estado remoto criptografado**
O tfstate fica num S3 com `encrypt = true`, versionamento habilitado e acesso público bloqueado. Permite rollback de estado corrompido.

**Idempotência no Ansible**
`kubeadm init` e `kubeadm join` verificam `/etc/kubernetes/admin.conf` e `/etc/kubernetes/kubelet.conf` antes de executar. Reexecutar o playbook num cluster já configurado não causa regressão.

---

## Pré-requisitos

### Local
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.10
- [Terragrunt](https://terragrunt.gruntwork.io/docs/getting-started/install/) >= 0.67
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) >= 10.x (via pip)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) >= 2
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [session-manager-plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)

### AWS
- Conta AWS com permissões para criar EC2, VPC, IAM, S3
- S3 bucket criado para o Terraform state (configurar em `root.hcl`)
- OIDC provider configurado para o GitHub Actions (módulo `aws-iam-oidc-github`)

---

## Configuração inicial

### 1. Clonar e configurar

```bash
git clone https://github.com/seu-usuario/k8sadmin-aws.git
cd k8sadmin-aws
```

Copie os arquivos de configuração e ajuste para o seu ambiente:

```bash
cp root.example.hcl root.hcl
cp ansible/inventory/aws_ec2.example.yml ansible/inventory/aws_ec2.yml
```

Edite `root.hcl`:
- `aws_region` — região AWS
- `project` — nome do projeto (usado nas tags)
- `bucket` — nome do seu S3 bucket para o tfstate

Edite `ansible/inventory/aws_ec2.yml`:
- `regions` — região AWS
- `ansible_aws_ssm_bucket_name` — mesmo bucket do tfstate

### 2. Instalar dependências do Ansible

```bash
cd ansible
python3 -m venv ../ansible-env
source ../ansible-env/bin/activate
pip install ansible boto3 botocore
ansible-galaxy collection install -r requirements.yml
```

### 3. Provisionar a infraestrutura

```bash
# Via GitHub Actions (recomendado):
# Disparar workflow_dispatch com action = apply

# Ou localmente:
cd environments/dev
terragrunt run-all apply
```

### 4. Configurar o cluster Kubernetes

```bash
cd ansible
source ../ansible-env/bin/activate
ansible-playbook playbooks/site.yml
```

### 5. Acessar o cluster

```bash
./scripts/k8s-connect.sh start
export KUBECONFIG=~/.kube/k8sadmin-aws.yaml
kubectl get nodes
```

---

## Scripts disponíveis

| Script | Descrição |
|---|---|
| `scripts/k8s-connect.sh start` | Inicia SSM port forward, copia kubeconfig e testa conexão |
| `scripts/k8s-connect.sh stop` | Encerra o port forward |
| `scripts/k8s-connect.sh status` | Verifica se o túnel está ativo e lista nodes |
| `scripts/rename-nodes.sh` | Renomeia nodes com IPs para nomes amigáveis (master-1, worker-1...) |

---

## Estrutura do projeto

```
k8sadmin-aws/
├── root.hcl                        # Config global do Terragrunt (provider, backend, tags)
├── root.example.hcl                # Template para configuração inicial
│
├── modules/                        # Módulos Terraform reutilizáveis
│   ├── aws-vpc/                    # VPC + subnet pública + IGW + route table
│   ├── aws-security-group/         # Security Group para o cluster K8s
│   ├── aws-ec2-instance/           # EC2 com IMDSv2, EBS encriptado, monitoring
│   ├── aws-iam-ec2/                # IAM Role + Instance Profile (SSM + ECR)
│   ├── aws-iam-oidc-github/        # OIDC provider + Role para GitHub Actions
│   ├── aws-s3-bucket/              # S3 com versionamento, encryption e logging
│   └── aws-keypair/                # Key pair (opcional)
│
├── environments/
│   └── dev/                        # Ambiente de desenvolvimento
│       ├── network/                # Instancia o módulo aws-vpc
│       ├── security-group/         # Instancia o módulo aws-security-group
│       ├── iam/                    # Instancia o módulo aws-iam-ec2
│       └── ec2/                    # Instancia o módulo aws-ec2-instance
│
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/
│   │   ├── aws_ec2.example.yml     # Template do inventário dinâmico
│   │   └── aws_ec2.yml             # Inventário dinâmico EC2 via SSM (não comitar dados sensíveis)
│   ├── group_vars/
│   │   ├── all.yml                 # k8s_version, kiro_install_url
│   │   ├── master.yml              # node_role: master
│   │   └── workers.yml             # node_role: worker
│   ├── playbooks/
│   │   ├── site.yml                # Playbook principal (common + containerd + master + worker)
│   │   └── reset.yml               # Destrói e limpa o cluster
│   └── roles/
│       ├── common/                 # Sistema base: kernel modules, sysctl, K8s packages
│       ├── containerd/             # Runtime de container com SystemdCgroup
│       ├── k8s_master/             # kubeadm init, kubeconfig, Flannel CNI
│       ├── k8s_worker/             # kubeadm join
│       └── kiro/                   # Agente Kiro (opcional)
│
├── scripts/
│   ├── k8s-connect.sh              # Gerencia acesso ao cluster via SSM port forward
│   └── rename-nodes.sh             # Renomeia nodes do cluster para nomes amigáveis
│
└── .github/
    └── workflows/
        └── k8sadmin-aws.yaml       # Pipeline: plan / apply / destroy via OIDC
```

---

## CI/CD

O workflow `.github/workflows/k8sadmin-aws.yaml` é acionado manualmente (`workflow_dispatch`) com três opções:

| Ação | O que faz |
|---|---|
| `plan` | Mostra o que será criado/alterado sem aplicar |
| `apply` | Provisiona ou atualiza a infraestrutura |
| `destroy` | Destrói todos os recursos |

A autenticação com a AWS usa **OIDC** — o GitHub gera um token JWT que a AWS valida diretamente, sem nenhuma chave de acesso armazenada. Configurar o secret `AWS_ROLE_ARN` com o ARN da role criada pelo módulo `aws-iam-oidc-github`.

---

## Reset do cluster

Para destruir e recriar o cluster Kubernetes sem mexer na infra:

```bash
cd ansible
ansible-playbook playbooks/reset.yml   # limpa kubeadm, CNI e iptables
ansible-playbook playbooks/site.yml    # recria o cluster
```
