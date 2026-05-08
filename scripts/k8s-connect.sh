#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# k8s-connect.sh — acesso ao cluster k8sadmin-aws via SSM port forward
#
# Uso:
#   ./scripts/k8s-connect.sh start    inicia port forward e copia kubeconfig
#   ./scripts/k8s-connect.sh stop     encerra o port forward
#   ./scripts/k8s-connect.sh status   mostra se o túnel está ativo
# ---------------------------------------------------------------------------

REGION="us-east-1"
PROJECT_TAG="k8sadmin-aws"
MASTER_NAME="master-1"
LOCAL_PORT="6443"
REMOTE_PORT="6443"
KUBECONFIG_PATH="${HOME}/.kube/k8sadmin-aws.yaml"
PID_FILE="/tmp/k8sadmin-ssm-forward.pid"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}✔${NC}  $1"; }
info() { echo -e "${CYAN}→${NC}  $1"; }
warn() { echo -e "${YELLOW}!${NC}  $1"; }
err()  { echo -e "${RED}✘${NC}  $1" >&2; exit 1; }

# ---------------------------------------------------------------------------
cmd_start() {
  # 1. Localizar master
  info "Buscando instância ${MASTER_NAME}..."
  MASTER_ID=$(aws ec2 describe-instances \
    --filters \
      "Name=tag:Name,Values=${MASTER_NAME}" \
      "Name=tag:Project,Values=${PROJECT_TAG}" \
      "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].InstanceId" \
    --output text \
    --region "${REGION}")

  [[ "${MASTER_ID}" == "None" || -z "${MASTER_ID}" ]] && \
    err "Master não encontrado. Verifique se o cluster está rodando."
  log "Master: ${MASTER_ID}"

  # 2. Copiar kubeconfig via SSM Run Command
  info "Copiando kubeconfig do master..."
  mkdir -p "$(dirname "${KUBECONFIG_PATH}")"

  COMMAND_ID=$(aws ssm send-command \
    --instance-ids "${MASTER_ID}" \
    --document-name "AWS-RunShellScript" \
    --parameters '{"commands":["cat /root/.kube/config"]}' \
    --query "Command.CommandId" \
    --output text \
    --region "${REGION}")

  aws ssm wait command-executed \
    --command-id "${COMMAND_ID}" \
    --instance-id "${MASTER_ID}" \
    --region "${REGION}"

  aws ssm get-command-invocation \
    --command-id "${COMMAND_ID}" \
    --instance-id "${MASTER_ID}" \
    --query "StandardOutputContent" \
    --output text \
    --region "${REGION}" > "${KUBECONFIG_PATH}"

  [[ ! -s "${KUBECONFIG_PATH}" ]] && err "Kubeconfig vazio. Verifique se o cluster foi inicializado."

  # 3. Ajustar server para 127.0.0.1 (127.0.0.1 está no SAN do cert desde kubeadm init)
  sed -i "s|server: https://.*:${REMOTE_PORT}|server: https://127.0.0.1:${LOCAL_PORT}|" "${KUBECONFIG_PATH}"

  log "Kubeconfig salvo em ${KUBECONFIG_PATH}"

  # 4. Encerrar port forward anterior se existir
  if [[ -f "${PID_FILE}" ]]; then
    OLD_PID=$(cat "${PID_FILE}")
    if kill -0 "${OLD_PID}" 2>/dev/null; then
      warn "Encerrando port forward anterior (PID ${OLD_PID})..."
      kill "${OLD_PID}" && sleep 1
    fi
    rm -f "${PID_FILE}"
  fi

  # 5. Iniciar port forward em background
  info "Iniciando SSM port forward  localhost:${LOCAL_PORT} → ${MASTER_ID}:${REMOTE_PORT}..."
  aws ssm start-session \
    --target "${MASTER_ID}" \
    --document-name "AWS-StartPortForwardingSession" \
    --parameters "{\"portNumber\":[\"${REMOTE_PORT}\"],\"localPortNumber\":[\"${LOCAL_PORT}\"]}" \
    --region "${REGION}" &>/tmp/k8sadmin-ssm.log &

  SSM_PID=$!
  echo "${SSM_PID}" > "${PID_FILE}"

  # 6. Aguardar porta ficar disponível (máx 20s)
  info "Aguardando porta ${LOCAL_PORT}..."
  for i in $(seq 1 20); do
    if nc -z 127.0.0.1 "${LOCAL_PORT}" 2>/dev/null; then break; fi
    if ! kill -0 "${SSM_PID}" 2>/dev/null; then
      err "Port forward encerrou inesperadamente. Veja /tmp/k8sadmin-ssm.log"
    fi
    sleep 1
  done

  nc -z 127.0.0.1 "${LOCAL_PORT}" 2>/dev/null || err "Porta ${LOCAL_PORT} não respondeu. Veja /tmp/k8sadmin-ssm.log"

  # 7. Testar kubectl
  info "Verificando cluster..."
  if KUBECONFIG="${KUBECONFIG_PATH}" kubectl get nodes 2>/dev/null; then
    echo ""
    log "Cluster acessível. Execute em seu shell:"
    echo ""
    echo -e "    ${CYAN}export KUBECONFIG=${KUBECONFIG_PATH}${NC}"
    echo ""
    warn "Port forward ativo (PID ${SSM_PID}). Para encerrar: $0 stop"
  else
    err "kubectl não conseguiu conectar. Verifique /tmp/k8sadmin-ssm.log"
  fi
}

# ---------------------------------------------------------------------------
cmd_stop() {
  if [[ ! -f "${PID_FILE}" ]]; then
    warn "Nenhum port forward ativo encontrado."
    return
  fi
  PID=$(cat "${PID_FILE}")
  if kill -0 "${PID}" 2>/dev/null; then
    kill "${PID}"
    log "Port forward encerrado (PID ${PID})."
  else
    warn "Processo ${PID} já não estava rodando."
  fi
  rm -f "${PID_FILE}"
}

# ---------------------------------------------------------------------------
cmd_status() {
  if [[ ! -f "${PID_FILE}" ]]; then
    warn "Port forward: inativo"
    return
  fi
  PID=$(cat "${PID_FILE}")
  if kill -0 "${PID}" 2>/dev/null; then
    log "Port forward: ativo (PID ${PID})"
    if nc -z 127.0.0.1 "${LOCAL_PORT}" 2>/dev/null; then
      log "Porta localhost:${LOCAL_PORT}: respondendo"
      if [[ -f "${KUBECONFIG_PATH}" ]]; then
        echo ""
        KUBECONFIG="${KUBECONFIG_PATH}" kubectl get nodes
      fi
    else
      warn "Porta localhost:${LOCAL_PORT}: não responde"
    fi
  else
    warn "Port forward: PID ${PID} não existe mais"
    rm -f "${PID_FILE}"
  fi
}

# ---------------------------------------------------------------------------
case "${1:-}" in
  start)  cmd_start  ;;
  stop)   cmd_stop   ;;
  status) cmd_status ;;
  *)
    echo "Uso: $0 {start|stop|status}"
    exit 1
    ;;
esac
