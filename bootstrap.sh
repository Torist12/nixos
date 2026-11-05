#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Uso: bootstrap.sh [opções]

Cria ou reaproveita a configuração do NixOS em /etc/nixos e aplica o flake do host.

Opções:
  --repo URL            Repositório Git remoto. (padrão: https://github.com/Torist12/nixos.git)
  --branch NOME         Branch do remoto a ser clonada. (padrão: master)
  --host NOME           Host do flake a ser usado. (padrão: konqi)
  --dry-run             Executa apenas validações e dry-build; não clona nem move /etc/nixos
  --no-switch           Prepara a configuração, mas não aplica o rebuild
  -h, --help            Mostra esta ajuda

Variáveis de ambiente:
  REPO, BRANCH, HOST

Precedência: flag > variável de ambiente > padrão.

Exemplos:
  BRANCH=dev bash bootstrap.sh
  bash bootstrap.sh --branch dev --host konqi --dry-run
  bash bootstrap.sh --repo https://github.com/Torist12/nixos.git --no-switch
EOF
}

info() {
  printf '\n==> %s\n' "$*"
}

warn() {
  printf '\nAVISO: %s\n' "$*" >&2
}

die() {
  printf '\nERRO: %s\n' "$*" >&2
  exit 1
}

REPO="${REPO:-https://github.com/Torist12/nixos.git}"
BRANCH="${BRANCH:-master}"
HOST="${HOST:-konqi}"
DRY_RUN=0
NO_SWITCH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || die "A flag --repo precisa de um valor."
      REPO="$2"
      shift 2
      ;;
    --branch)
      [[ $# -ge 2 ]] || die "A flag --branch precisa de um valor."
      BRANCH="$2"
      shift 2
      ;;
    --host)
      [[ $# -ge 2 ]] || die "A flag --host precisa de um valor."
      HOST="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --no-switch)
      NO_SWITCH=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Opção desconhecida: $1"
      ;;
  esac
done

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  die "Execute este script como usuário normal. Ele usa sudo quando necessário."
fi

if [[ ! -f /etc/os-release ]]; then
  die "Arquivo /etc/os-release não encontrado. Não foi possível confirmar que o sistema é NixOS."
fi

if ! grep -Eq '^ID="?nixos"?$' /etc/os-release; then
  die "Este sistema não parece ser NixOS. O /etc/os-release deve declarar ID=nixos."
fi

if ! command -v git >/dev/null 2>&1; then
  die "git não está instalado. Para instalar: nix-shell -p git --run 'git --version'"
fi

if ! command -v sudo >/dev/null 2>&1; then
  die "sudo não está instalado ou não está no PATH. Instale antes de continuar."
fi

if ! git ls-remote --heads "$REPO" >/dev/null 2>&1; then
  die "Não foi possível acessar o repositório remoto '$REPO'. Verifique a internet e o acesso ao GitHub. Se o repositório for privado, faça 'gh auth login' ou configure o acesso antes de continuar."
fi

if ! git ls-remote --exit-code --heads "$REPO" "$BRANCH" >/dev/null 2>&1; then
  die "A branch '$BRANCH' não existe em '$REPO'. Verifique o nome da branch e tente outra."
fi

print_checklist() {
  cat <<'EOF'

Checklist final - itens que não vêm no repositório por intenção:
  - sudo passwd will
  - fprintd-enroll
  - sudo tailscale up
  - conectar as APIs no OpenCode com /connect
  - llama-on, se quiser a IA local (o modelo de ~1,6 GB baixa na primeira ativação do Home Manager)
EOF
}

if (( DRY_RUN )); then
  info "Modo dry-run ativado. O script apenas mostrará o que faria e executará um dry-build sem tocar em /etc/nixos."
  repo_dir="${PWD}"
  if [[ -d /etc/nixos && -d /etc/nixos/.git ]]; then
    repo_dir="/etc/nixos"
  fi
  info "Repositório de origem: ${repo_dir}"
  info "Repositório remoto: ${REPO}"
  info "Branch: ${BRANCH}"
  info "Host: ${HOST}"
  info "Comando que seria executado: sudo nixos-rebuild dry-build --flake ${repo_dir}#${HOST}"
  if ! (cd "$repo_dir" && nix eval --raw ".#nixosConfigurations.${HOST}.config.system.build.toplevel.drvPath" >/dev/null 2>&1); then
    die "O host '$HOST' não existe no flake do diretório '${repo_dir}'."
  fi
  sudo nixos-rebuild dry-build --flake "${repo_dir}#${HOST}"
  info "Dry-run concluído; nada foi movido nem apagado em /etc/nixos."
  exit 0
fi

if [[ -d /etc/nixos ]]; then
  timestamp="$(date +%Y%m%d-%H%M%S)"
  backup="/etc/nixos.bak-${timestamp}"
  info "Diretório /etc/nixos já existe. Movendo para ${backup}"
  sudo mv /etc/nixos "$backup"
  warn "Backup criado em ${backup}."
fi

TARGET="/etc/nixos"
info "Clonando ${REPO} (${BRANCH}) em ${TARGET}"
sudo git clone --branch "$BRANCH" "$REPO" "$TARGET"

info "Devolvendo a posse do repositório ao usuário atual"
sudo chown -R "${USER}:users" "$TARGET"

if [[ ! -d "$TARGET/.git" ]]; then
  die "O clone em '$TARGET' não parece ter sido criado corretamente."
fi

if ! command -v nix >/dev/null 2>&1; then
  die "nix não está disponível no PATH. O ambiente de bootstrap precisa do Nix para montar o flake e aplicar a configuração."
fi

if ! (cd "$TARGET" && nix eval --raw ".#nixosConfigurations.${HOST}.config.system.build.toplevel.drvPath" >/dev/null 2>&1); then
  die "O host '$HOST' não existe no flake de '$TARGET'. Verifique o nome do host do flake antes de aplicar."
fi

hardware_file="$TARGET/hardware-configuration.nix"
info "Gerando hardware da máquina atual em ${hardware_file}"
if git -C "$TARGET" ls-files --error-unmatch hardware-configuration.nix >/dev/null 2>&1; then
  git -C "$TARGET" add -N hardware-configuration.nix
else
  git -C "$TARGET" add -N -f hardware-configuration.nix || true
fi
sudo bash -c 'nixos-generate-config --show-hardware-config > "$1"' _ "$hardware_file"
if git -C "$TARGET" ls-files --error-unmatch hardware-configuration.nix >/dev/null 2>&1; then
  git -C "$TARGET" add -N hardware-configuration.nix
else
  git -C "$TARGET" add -N -f hardware-configuration.nix || true
fi

info "Validando a configuração antes de aplicar"
sudo nixos-rebuild dry-build --flake "${TARGET}#${HOST}"

if (( NO_SWITCH )); then
  info "Flag --no-switch usada: a configuração foi preparada, validada e não foi aplicada no sistema."
  print_checklist
  exit 0
fi

info "Aplicando a configuração do host '${HOST}'"
sudo nixos-rebuild switch --flake "${TARGET}#${HOST}"

print_checklist
info "Bootstrap concluído. Repositório em ${TARGET}."
