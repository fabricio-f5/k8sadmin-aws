# k8sadmin-aws

Provisionamento e configuração de um cluster Kubernetes na AWS usando Terraform, Terragrunt e Ansible — sem SSH, sem bastião, acesso 100% via AWS SSM.

---

## O que este projeto faz

Sobe um cluster Kubernetes de 3 nós (1 control-plane + 2 workers) na AWS do zero:

1. **Infra** — VPC (pública + privada), NAT Gateway, VPC Endpoints, Security Groups, IAM roles, S3 dedicado e instâncias EC2 provisionados via Terraform/Terragrunt
2. **Cluster** — containerd, kubeadm, Calico CNI, nginx Ingress Controller e kubectl instalados e configurados via Ansible
3. **Acesso seguro** — todo acesso às instâncias é feito via AWS SSM Session Manager (sem portas abertas, sem chaves SSH expostas)
4. **CI/CD** — GitHub Actions aplica/destroi a infra usando OIDC (sem `AWS_ACCESS_KEY_ID` armazenado)

---

## Arquitetura

```
┌──────────────────────────────────────────────────────────────────┐
│  AWS  (us-east-1)                                                 │
│                                                                   │
│  ┌─── VPC 10.0.0.0/16 ───────────────────────────────────────┐  │
│  │                                                             │  │
│  │  Subnet pública 10.0.1.0/24                                 │  │
│  │  ┌──────────────┐                                           │  │
│  │  │  NAT Gateway │ ◄── EIP                                   │  │
│  │  └──────┬───────┘                                           │  │
│  │         │                                                   │  │
│  │  Subnet privada 10.0.2.0/24                                 │  │
│  │                                                             │  │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐            │  │
│  │  │  master-1  │  │  worker-1  │  │  worker-2  │            │  │
│  │  │  t3.small  │  │  t3.small  │  │  t3.small  │            │  │
│  │  │ control-   │  │            │  │            │            │  │
│  │  │  plane     │  │            │  │            │            │  │
│  │  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘            │  │
│  │        └───────────────┴───────────────┘                   │  │
│  │              Security Group (K8s ports + Ingress)           │  │
│  │                                                             │  │
│  │  VPC Endpoints: ssm · ssmmessages · ec2messages · s3        │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                           │                                       │
│              IAM Role  +  SSM Agent                               │
│                           │                                       │
│         ┌─────────────────┘                                      │
│         │  SSM Session Manager                                    │
│         │  (sem SSH / sem porta 22)                               │
│                                                                   │
│  S3: tfstate (encrypted + versioned)                             │
│  S3: k8sadmin-aws-ssm-dev (SSM session files, lifecycle 30d)     │
└──────────────────────────────────────────────────────────────────┘
         │                        │
   GitHub Actions            Ansible (local ou CI)
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
| CNI | Calico | v3.28 |
| Ingress | nginx Ingress Controller | v1.10.1 |
| CI/CD | GitHub Actions + OIDC | — |
| Acesso remoto | AWS SSM Session Manager | — |

---

## Decisões técnicas relevantes

**SSM em vez de SSH**
Nenhuma porta 22 aberta, nenhuma chave `.pem` distribuída. O acesso às instâncias usa o SSM Agent pré-instalado nas AMIs Ubuntu e a IAM role `AmazonSSMManagedInstanceCore`. Elimina a superfície de ataque do bastião.

**Nodes em subnet privada + NAT Gateway**
Nenhum nó do cluster tem IP público. A subnet privada (`10.0.2.0/24`) não tem rota direta para a internet — o tráfego de saída passa pelo NAT Gateway na subnet pública. Reduz a superfície de ataque dos nodes.

**VPC Endpoints para SSM e S3**
O tráfego do SSM Session Manager e do S3 (tfstate, bucket SSM) trafega dentro da rede AWS via VPC Endpoints, sem passar pela internet pública. Mais seguro e sem custo de transferência de dados.

**Calico como CNI (NetworkPolicy)**
O Flannel não implementa `NetworkPolicy` — qualquer pod consegue falar com qualquer outro. O Calico implementa NetworkPolicy nativamente, permitindo isolamento de rede entre workloads (ex: front-end não acessa banco diretamente).

**nginx Ingress Controller**
Expõe serviços HTTP/HTTPS de forma padronizada via recursos `Ingress`, com roteamento por hostname/path e TLS centralizado. Alternativa ao NodePort direto, que expõe portas aleatórias sem roteamento.

**Certificado do API Server com SAN 127.0.0.1**
O kubeadm é inicializado com `--apiserver-cert-extra-sans=127.0.0.1`. Isso permite que o `k8s-connect.sh` faça port forward via SSM e use `https://127.0.0.1:6443` sem precisar desabilitar a verificação TLS.

**Bucket S3 dedicado para o SSM**
O SSM Session Manager usa um bucket S3 separado (`k8sadmin-aws-ssm-dev`) para transferência de arquivos durante as sessões Ansible. Mantém isolado do bucket de tfstate. Lifecycle de 30 dias expira os arquivos de sessão automaticamente.

**Terragrunt para DRY**
Em vez de duplicar `provider.tf` e `backend.tf` em cada módulo, o `root.hcl` os gera automaticamente. Adicionar um novo ambiente exige criar um único `terragrunt.hcl` referenciando o módulo.

**OIDC no GitHub Actions**
O workflow assume uma IAM role via token OIDC do GitHub. Nenhuma `AWS_SECRET_ACCESS_KEY` armazenada como secret — elimina o risco de vazamento de credenciais estáticas.

**IMDSv2 obrigatório**
Todas as instâncias têm `http_tokens = required`. Impede ataques SSRF que tentam extrair credenciais da metadata API.

**Estado remoto criptografado**
O tfstate fica num S3 com `encrypt = true`, versionamento habilitado e acesso público bloqueado. Permite rollback de estado via `aws s3api list-object-versions`.

**Idempotência no Ansible**
`kubeadm init` e `kubeadm join` verificam `/etc/kubernetes/admin.conf` e `/etc/kubernetes/kubelet.conf` antes de executar. Reexecutar o playbook num cluster já configurado não causa regressão.

**Bootstrap sem lock circular**
O diretório `bootstrap/` tem seu próprio `root.hcl` sem lock file — ele cria a IAM role OIDC sem depender de nada que ainda não existe. O `root.hcl` principal ativa o lock (`use_lockfile = true`) depois que o bootstrap rodou.

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
- `ansible_aws_ssm_bucket_name` — bucket SSM dedicado (`k8sadmin-aws-ssm-dev` por padrão)

### 2. Instalar dependências do Ansible

```bash
cd ansible
python3 -m venv ../ansible-env
source ../ansible-env/bin/activate
pip install ansible boto3 botocore
ansible-galaxy collection install -r requirements.yml
```

### 3. Bootstrap (executar uma vez, localmente)

O bootstrap cria a IAM role OIDC para o GitHub Actions. Deve ser executado localmente com credenciais AWS antes de qualquer `apply` na infra principal.

```bash
cd bootstrap/oidc
terragrunt apply
```

Após o apply, copie o ARN da role exibido no output e adicione como secret `AWS_ROLE_ARN` no repositório GitHub:
**Settings → Secrets and variables → Actions → New repository secret**

### 4. Provisionar a infraestrutura

A ordem de apply respeita as dependências entre módulos:

```bash
# Via GitHub Actions (recomendado): disparar workflow_dispatch com action = apply

# Ou localmente, na ordem correta:
cd environments/dev
terragrunt run --all apply --parallelism 1
```

Ordem manual se necessário: `bootstrap/oidc` → `network` → `security-group` → `ssm-bucket` → `iam` → `ec2`

### 5. Configurar o cluster Kubernetes

```bash
cd ansible
source ../ansible-env/bin/activate

# Gerar inventário dinâmico
sed "s|<NOME_DO_BUCKET>|k8sadmin-aws-ssm-dev|g" \
  inventory/aws_ec2.example.yml > inventory/aws_ec2.yml

ansible-playbook playbooks/site.yml
```

O playbook instala: containerd → kubeadm/kubelet/kubectl → inicializa o cluster → Calico CNI → workers → nginx Ingress Controller.

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
├── root.hcl                        # Config global do Terragrunt (gitignored — copiar do root.example.hcl)
├── root.example.hcl                # Template: copiar para root.hcl e ajustar
│
├── bootstrap/                      # Executar uma vez, localmente, antes do CI/CD
│   ├── root.hcl                    # Config do Terragrunt para o bootstrap
│   ├── dynamodb/                   # Cria a tabela DynamoDB de lock do tfstate
│   └── oidc/                       # Cria IAM role + OIDC provider para GitHub Actions
│
├── modules/                        # Módulos Terraform reutilizáveis
│   ├── aws-vpc/                    # VPC + subnet pública/privada + IGW + NAT + VPC Endpoints
│   ├── aws-security-group/         # Security Group para o cluster K8s (+ Ingress 80/443)
│   ├── aws-ec2-instance/           # EC2 com IMDSv2, EBS encriptado, monitoring
│   ├── aws-iam-ec2/                # IAM Role + Instance Profile (SSM + S3 SSM bucket)
│   ├── aws-iam-oidc-github/        # OIDC provider + Role para GitHub Actions
│   ├── aws-dynamodb-lock/          # Tabela DynamoDB para lock do Terraform state
│   └── aws-s3-ssm/                 # Bucket S3 dedicado para SSM (lifecycle 30d)
│
├── environments/
│   └── dev/                        # Ambiente de desenvolvimento
│       ├── network/                # VPC + subnets + NAT + VPC Endpoints
│       ├── security-group/         # Security Group do cluster
│       ├── ssm-bucket/             # Bucket S3 para SSM (k8sadmin-aws-ssm-dev)
│       ├── iam/                    # IAM Role + Instance Profile
│       └── ec2/                    # Instâncias EC2 (master-1, worker-1, worker-2)
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
│   │   ├── site.yml                # Playbook principal (common + containerd + master + worker + ingress)
│   │   └── reset.yml               # Destrói e limpa o cluster
│   └── roles/
│       ├── common/                 # Sistema base: kernel modules, sysctl, K8s packages
│       ├── containerd/             # Runtime de container com SystemdCgroup
│       ├── k8s_master/             # kubeadm init, kubeconfig, Calico CNI
│       └── k8s_worker/             # kubeadm join
│
├── scripts/
│   └── k8s-connect.sh              # Gerencia acesso ao cluster via SSM port forward
│
└── .github/
    └── workflows/
        ├── k8sadmin-aws.yaml       # Pipeline: plan / apply / plan-destroy / destroy via OIDC
        └── ansible.yaml            # Pipeline: check / site / reset via OIDC
```

---

## CI/CD

### Secrets necessários

Configure em **Settings → Secrets and variables → Actions**:

| Secret | Descrição |
|---|---|
| `AWS_ROLE_ARN` | ARN da IAM role criada no bootstrap (`bootstrap/oidc`) |
| `AWS_SSM_BUCKET_NAME` | Nome do bucket SSM dedicado — padrão: `k8sadmin-aws-ssm-dev` |
| `TF_STATE_BUCKET` | Nome do bucket S3 para o tfstate — padrão: `k8sadmin-aws-tfstate` |

---

### Workflow: Infraestrutura (`k8sadmin-aws.yaml`)

Acionado manualmente via `workflow_dispatch`. Gerencia os recursos AWS via Terragrunt.

| Ação | O que faz |
|---|---|
| `plan` | Mostra o que será criado/alterado sem aplicar |
| `apply` | Provisiona ou atualiza a infraestrutura |
| `plan-destroy` | Mostra o que seria destruído sem executar |
| `destroy` | Destrói todos os recursos (requer aprovação manual) |

### Workflow: Ansible (`ansible.yaml`)

Acionado manualmente via `workflow_dispatch`. Configura o cluster Kubernetes nas instâncias EC2.

| Ação | O que faz |
|---|---|
| `check` | Dry-run com `--check --diff`: mostra o que seria alterado sem executar |
| `site` | Executa o playbook completo: instala e configura o cluster + Ingress |
| `reset` | Destroi e limpa o cluster (requer aprovação manual) |

A autenticação com a AWS usa **OIDC** nos dois workflows — o GitHub gera um token JWT que a AWS valida diretamente, sem nenhuma chave de acesso armazenada.

### Proteção das ações destrutivas

Os jobs `destroy` (infra) e `reset` (Ansible) usam **GitHub Environments** com aprovação obrigatória. Configure antes de usar:

1. No GitHub: **Settings → Environments → New environment**
2. Crie dois environments: `destroy` e `reset`
3. Em cada um: marque **Required reviewers** e adicione os aprovadores

Ao disparar essas ações, o GitHub pausará o job e notificará os revisores. A execução só ocorre após aprovação explícita.

---

## Reset do cluster

Para destruir e recriar o cluster Kubernetes sem mexer na infra:

```bash
cd ansible
ansible-playbook playbooks/reset.yml   # limpa kubeadm, CNI e iptables
ansible-playbook playbooks/site.yml    # recria o cluster
```
