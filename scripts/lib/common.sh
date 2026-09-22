#!/bin/bash
# Funções compartilhadas de log e validação para os scripts run_pyscenic_*.sh.
# Este arquivo deve ser incluído (source), não executado diretamente.

# Cores (desativadas automaticamente quando a saída não é um terminal)
if [ -t 1 ]; then
    C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'; C_RESET='\033[0m'
else
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_RESET=''
fi

log_info()  { echo -e "${C_BLUE}[INFO]${C_RESET} $*"; }
log_ok()    { echo -e "${C_GREEN}[ OK ]${C_RESET} $*"; }
log_warn()  { echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
log_error() { echo -e "${C_RED}[FAIL]${C_RESET} $*" >&2; }

# require_file <caminho> <descrição>
# Retorna 1 (sem abortar o script) se o arquivo não existir ou estiver vazio.
require_file() {
    local path="$1" desc="$2"
    if [ -z "$path" ]; then
        log_error "$desc: caminho vazio no CSV"
        return 1
    fi
    if [ ! -f "$path" ]; then
        log_error "$desc não encontrado: $path"
        return 1
    fi
    if [ ! -s "$path" ]; then
        log_error "$desc está vazio (0 bytes): $path"
        return 1
    fi
    return 0
}

# validate_csv_output <caminho> <col1> [col2 ...]
# Verifica se o arquivo de saída existe, não está vazio e contém as colunas
# esperadas no cabeçalho (correspondência por substring, ordem não é exigida).
# Retorna o número de linhas de dados (excluindo o cabeçalho) por meio da
# variável global VALIDATE_NROWS.
validate_csv_output() {
    local path="$1"; shift
    local expected_cols=("$@")

    if [ ! -f "$path" ]; then
        log_error "a saída não foi criada: $path"
        return 1
    fi
    if [ ! -s "$path" ]; then
        log_error "a saída está vazia (0 bytes): $path"
        return 1
    fi

    # o pyscenic ctx grava um cabeçalho de múltiplas linhas (MultiIndex do
    # pandas), então buscamos nas primeiras linhas em vez de apenas na primeira.
    local header
    header=$(head -n 3 "$path")
    local col
    for col in "${expected_cols[@]}"; do
        if [[ "$header" != *"$col"* ]]; then
            log_error "coluna esperada '$col' não encontrada no início de $path"
            return 1
        fi
    done

    VALIDATE_NROWS=$(( $(wc -l < "$path") - 1 ))
    if [ "$VALIDATE_NROWS" -le 0 ]; then
        log_error "a saída não tem linhas de dados: $path"
        return 1
    fi
    return 0
}

# Linhas correspondentes aqui são removidas apenas do stream AO VIVO no
# terminal — a saída completa e sem filtros sempre vai integralmente para o
# arquivo de log. São avisos que o pyscenic/ctxcore imprimem de forma
# idêntica em toda execução (avisos de depreciação de dependências, uma nota
# estática sobre cálculo de correlação) e não agregam nada depois que você já
# os viu uma vez, mas ficam muito repetitivos ao longo de várias linhas de um CSV.
NOISY_LIVE_PATTERN='pkg_resources is deprecated|from pkg_resources import|Note on correlation calculation|Previously, the default was to calculate|current default is now to use all cells|The original settings can be retained|Dropout masking is currently set to'

# run_and_log <arquivo_log> -- <comando...>
# Executa o comando, salvando stdout+stderr no arquivo de log. Por padrão,
# também transmite ao vivo para o terminal (filtrando NOISY_LIVE_PATTERN
# apenas do que é exibido ao vivo, não do arquivo de log), e retorna o
# código de saída do comando (deliberadamente sem usar 'set -e' aqui — quem
# chama decide o que fazer em caso de falha).
#
# Transmitir ao vivo importa aqui: com --mode dask_multiprocessing, o
# "pyscenic ctx" já imprime uma barra de progresso percentual real
# (dask.diagnostics.ProgressBar) no stdout, e o "pyscenic grn" imprime
# mensagens de marco (milestone) ("Loading expression matrix.", "Inferring
# regulatory networks.", ...) — ambas ficavam ocultas até o fim da execução,
# pois a saída ia apenas para o arquivo de log.
#
# Defina QUIET=1 (veja --quiet nos scripts que chamam esta função) para
# voltar ao comportamento antigo: nenhuma saída ao vivo, apenas o arquivo de
# log — útil para execuções não supervisionadas (nohup/cron) onde ninguém
# está observando o terminal.
run_and_log() {
    local logfile="$1"; shift
    if [ "$1" == "--" ]; then shift; fi
    local start_ts end_ts
    RUN_STARTED_AT=$(date -Iseconds)
    start_ts=$(date +%s)
    if [ "${QUIET:-0}" -eq 1 ]; then
        "$@" > "$logfile" 2>&1
        local rc=$?
    else
        "$@" 2>&1 | tee "$logfile" | grep -Ev "$NOISY_LIVE_PATTERN"
        local rc=${PIPESTATUS[0]}
    fi
    end_ts=$(date +%s)
    RUN_FINISHED_AT=$(date -Iseconds)
    RUN_ELAPSED_SECONDS=$(( end_ts - start_ts ))
    return $rc
}

# nproc_check <num_workers>
# Apenas avisa (não bloqueia) se num_workers exceder os núcleos disponíveis.
nproc_check() {
    local requested="$1"
    local available
    available=$(nproc 2>/dev/null || echo "?")
    if [ "$available" != "?" ] && [ "$requested" -gt "$available" ]; then
        log_warn "num_workers=$requested é maior que os $available núcleos disponíveis nesta máquina"
    fi
}

# file_size_bytes <caminho>
# Imprime o tamanho do arquivo em bytes, ou 0 se o arquivo não existir. Usado
# para a telemetria leve nos CSVs de resumo e no JSON de metadados por execução.
file_size_bytes() {
    local path="$1"
    if [ -f "$path" ]; then
        stat -c%s "$path" 2>/dev/null || wc -c < "$path"
    else
        echo 0
    fi
}

# json_escape <string>
# Escape mínimo de string JSON (barras invertidas e aspas duplas — suficiente
# para os caminhos/hostnames/comandos que de fato colocamos nos arquivos de
# metadados).
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

# write_run_metadata_json <caminho_json> <chave1> <valor1> [<chave2> <valor2> ...]
# Grava um pequeno objeto JSON com metadados da execução (parâmetros,
# timestamps, tamanho da saída, etc.) ao lado do arquivo de log, para análise
# programática posterior (ex.: agregar estatísticas entre várias réplicas).
# Valores com aparência numérica são gravados sem aspas; todo o resto é
# colocado entre aspas e escapado.
write_run_metadata_json() {
    local json_path="$1"; shift
    local out="{" first=1
    while [ "$#" -ge 2 ]; do
        local key="$1" value="$2"; shift 2
        [ "$first" -eq 1 ] && first=0 || out+=","
        if [[ "$value" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
            out+="\"$key\":$value"
        else
            out+="\"$key\":\"$(json_escape "$value")\""
        fi
    done
    out+="}"
    printf '%s\n' "$out" > "$json_path"
}
