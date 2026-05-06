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
| Infra como código | Terraform + Terragrunt | ~1.10 / 1.0.3 |
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
Nenhuma porta 22 aberta, nenhuma chave `.pem` distribuída. O acesso às instâncias usa o SSM Agent pré-instalado nas AMIs Ubuntu e a IAM role `AmazonSSMManagedInstanceCore`. Elimina a superfície de ataque do bastião.

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

**Bootstrap sem lock circular**
O diretório `bootstrap/` tem seu próprio `root.hcl` sem `dynamodb_table` — ele cria a tabela DynamoDB de lock e a IAM role OIDC sem depender de nada que ainda não existe. O `root.hcl` principal só ativa o lock depois que o bootstrap rodou.

---

## Pré-requisitos

### Local
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.10
- [Terragrunt](https://terragrunt.gruntwork.io/docs/getting-started/install/) >= 1.0.3
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) >= 10.x (via pip)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) >= 2
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [session-manager-plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)

### AWS
- Conta AWS com permissões para criar EC2, VPC, IAM, S3, DynamoDB
- Credenciais configuradas localmente (`aws configure` ou variáveis de ambiente)

> O S3 bucket para o tfstate e a tabela DynamoDB de lock são criados automaticamente pelo Terragrunt (`TG_BACKEND_BOOTSTRAP=true`). A IAM role OIDC para o GitHub Actions é criada pelo step de bootstrap abaixo.

---

## Configuração inicial

### 1. Clonar e configurar

```bash
git clone https://github.com/fabricio-f5/k8sadmin-aws.git
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

### 3. Bootstrap (executar uma vez, localmente)

O bootstrap cria a tabela DynamoDB de lock e a IAM role OIDC para o GitHub Actions. Deve ser executado localmente com credenciais AWS antes de qualquer `apply` na infra principal.

```bash
# Criar a tabela DynamoDB de lock do Terraform state
cd bootstrap/dynamodb
terragrunt apply

# Criar a IAM role + OIDC provider para o GitHub Actions
cd ../oidc
terragrunt apply
```

Após o apply, copie o ARN da role exibido no output e adicione como secret `AWS_ROLE_ARN` no repositório GitHub:
**Settings → Secrets and variables → Actions → New repository secret**

### 4. Provisionar a infraestrutura

```bash
# Via GitHub Actions (recomendado):
# Disparar workflow_dispatch com action = apply

# Ou localmente:
cd environments/dev
terragrunt run --all apply
```

### 5. Configurar o cluster Kubernetes

```bash
cd ansible
source ../ansible-env/bin/activate
ansible-playbook playbooks/site.yml
```

### 6. Acessar o cluster

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

---

## Estrutura do projeto

```
k8sadmin-aws/
├── root.hcl                        # Config global do Terragrunt — gerado a partir do template (gitignored)
├── root.example.hcl                # Template: copiar para root.hcl e ajustar
│
├── bootstrap/                      # Executar uma vez, localmente, antes do CI/CD
│   ├── root.hcl                    # Config do Terragrunt para o bootstrap (gitignored)
│   ├── dynamodb/                   # Cria a tabela DynamoDB de lock do tfstate
│   └── oidc/                       # Cria IAM role + OIDC provider para GitHub Actions
│
├── modules/                        # Módulos Terraform reutilizáveis
│   ├── aws-vpc/                    # VPC + subnet pública + IGW + route table
│   ├── aws-security-group/         # Security Group para o cluster K8s
│   ├── aws-ec2-instance/           # EC2 com IMDSv2, EBS encriptado, monitoring
│   ├── aws-iam-ec2/                # IAM Role + Instance Profile (SSM)
│   ├── aws-iam-oidc-github/        # OIDC provider + Role para GitHub Actions
│   └── aws-dynamodb-lock/          # Tabela DynamoDB para lock do Terraform state
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
│   │   └── aws_ec2.yml             # Inventário dinâmico EC2 via SSM (gitignored)
│   ├── group_vars/
│   │   ├── all.yml                 # k8s_version
│   │   ├── master.yml              # Vars do grupo master
│   │   └── workers.yml             # Vars do grupo workers
│   ├── playbooks/
│   │   ├── site.yml                # Playbook principal (common + containerd + master + worker)
│   │   └── reset.yml               # Destrói e limpa o cluster
│   └── roles/
│       ├── common/                 # Sistema base: kernel modules, sysctl, K8s packages
│       ├── containerd/             # Runtime de container com SystemdCgroup
│       ├── k8s_master/             # kubeadm init, kubeconfig, Flannel CNI
│       └── k8s_worker/             # kubeadm join
│
├── scripts/
│   └── k8s-connect.sh              # Gerencia acesso ao cluster via SSM port forward
│
└── .github/
    └── workflows/
        └── k8sadmin-aws.yaml       # Pipeline: plan / apply / plan-destroy / destroy via OIDC
```

---

## CI/CD

O workflow `.github/workflows/k8sadmin-aws.yaml` é acionado manualmente (`workflow_dispatch`) com quatro opções:

| Ação | O que faz |
|---|---|
| `plan` | Mostra o que será criado/alterado sem aplicar |
| `apply` | Provisiona ou atualiza a infraestrutura |
| `plan-destroy` | Mostra o que seria destruído sem executar |
| `destroy` | Destrói todos os recursos (requer aprovação manual) |

A autenticação com a AWS usa **OIDC** — o GitHub gera um token JWT que a AWS valida diretamente, sem nenhuma chave de acesso armazenada. Configure o secret `AWS_ROLE_ARN` com o ARN da role criada no step de bootstrap.

### Proteção do destroy

O job `destroy` usa um **GitHub Environment** com aprovação obrigatória. Antes de usar, configure:

1. No GitHub: **Settings → Environments → New environment** → nome: `destroy`
2. Marque **Required reviewers** e adicione os aprovadores
3. Salve a proteção

Ao disparar o workflow com `destroy`, o GitHub pausará o job e enviará notificação aos revisores. Somente após aprovação a destruição é executada.

---

## Reset do cluster

Para destruir e recriar o cluster Kubernetes sem mexer na infra:

```bash
cd ansible
ansible-playbook playbooks/reset.yml   # limpa kubeadm, CNI e iptables
ansible-playbook playbooks/site.yml    # recria o cluster
```
