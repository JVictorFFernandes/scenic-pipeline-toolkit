#!/bin/bash
#
# Executa "pyscenic grn" para cada linha de um CSV de configuração, com
# validação de entrada/saída, log por execução e um resumo final.
#
# Uso:
#   bash scripts/run_pyscenic_grn.sh [config.csv] [--dry-run] [--force] [--quiet]
#
#   config.csv   caminho do CSV (padrão: artifacts/grn_runs.local.csv — gere-o
#                com scripts/generate_configs.py, não o escreva manualmente)
#   --dry-run    apenas valida os caminhos e imprime o comando, sem chamar o pyscenic
#   --force      reprocessa execuções mesmo se output_path já existir
#   --quiet      não transmite a saída do pyscenic ao vivo, apenas no arquivo de log (bom para nohup/cron)
#
# CSV esperado (com cabeçalho), colunas:
#   run_id,loom_path,tfs_path,output_path,num_workers,method,seed
#
# 'seed' é opcional (deixe a coluna vazia para uma seed aleatória a cada
# execução, seguindo o próprio padrão do pyscenic) — o
# scripts/generate_configs.py sempre a preenche (seed = número da réplica)
# para que as execuções sejam reprodutíveis.
#
set -uo pipefail  # sem -e: cada linha do CSV é tratada individualmente

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

CONFIG_CSV="artifacts/grn_runs.local.csv"
DRY_RUN=0
FORCE=0
QUIET=0

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --force) FORCE=1 ;;
        --quiet) QUIET=1 ;;
        *.csv) CONFIG_CSV="$arg" ;;
        *) log_error "argumento desconhecido: $arg"; exit 2 ;;
    esac
done

if [ ! -f "$CONFIG_CSV" ]; then
    log_error "arquivo de configuração não encontrado: $CONFIG_CSV"
    exit 2
fi

# generate_configs.py grava os CSVs em .../<project>/<cell-line>/configs/;
# os logs vão para .../<project>/<cell-line>/logs/, uma pasta irmã dessa
# pasta configs/ (não um logs/ global único) — assim, tudo sobre um
# projeto/linhagem celular (suas configurações, suas saídas e o que
# aconteceu durante a execução) fica reunido. Um CSV que não esteja dentro
# de uma pasta configs/ (ex.: artifacts/examples/*.csv, o smoke test) usa em
# vez disso uma pasta logs/ bem ao lado dele.
CSV_DIR="$(dirname "$CONFIG_CSV")"
if [ "$(basename "$CSV_DIR")" = "configs" ]; then
    ARTIFACT_DIR="$(dirname "$CSV_DIR")"
else
    ARTIFACT_DIR="$CSV_DIR"
fi
LOGS_DIR="$ARTIFACT_DIR/logs"
mkdir -p "$LOGS_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SUMMARY_CSV="$LOGS_DIR/grn_summary_${TIMESTAMP}.csv"
echo "run_id,status,n_edges,elapsed_seconds,output_size_bytes,num_workers,method,seed,started_at,finished_at,log_file" > "$SUMMARY_CSV"

# Total de linhas de dados, para o indicador de progresso "[i/N]" abaixo.
TOTAL_ROWS=$(tail -n +2 "$CONFIG_CSV" | grep -c '[^[:space:]]')

log_info "Usando configuração: $CONFIG_CSV ($TOTAL_ROWS execução(ões))"
[ "$DRY_RUN" -eq 1 ] && log_warn "modo --dry-run: nenhum comando pyscenic será executado de fato."

ANY_FAILED=0
ROW_NUM=0

# Lendo com IFS em um descritor de arquivo dedicado para que nada entre em
# conflito com o que o comando pyscenic possa ler do stdin.
while IFS=',' read -r run_id loom_path tfs_path output_path num_workers method seed || [ -n "$run_id" ]; do
    ROW_NUM=$((ROW_NUM + 1))
    [ "$ROW_NUM" -eq 1 ] && continue  # pula o cabeçalho
    [ -z "$run_id" ] && continue      # pula linhas em branco

    echo
    log_info "=== [$((ROW_NUM - 1))/$TOTAL_ROWS] [$run_id] ==="

    LOGFILE="$LOGS_DIR/grn_${run_id}.log"
    METAFILE="$LOGS_DIR/grn_${run_id}.meta.json"
    STATUS=""
    NEDGES=""
    RUN_ELAPSED_SECONDS=0
    RUN_STARTED_AT=""
    RUN_FINISHED_AT=""

    if ! require_file "$loom_path" "[$run_id] loom_path"; then
        STATUS="FAIL_INPUT"
    elif ! require_file "$tfs_path" "[$run_id] tfs_path"; then
        STATUS="FAIL_INPUT"
    fi

    # -s (não apenas -f): uma execução anterior que travou no meio da
    # gravação pode deixar um arquivo de saída de 0 bytes, que deve ser
    # reprocessado, não tratado como concluído.
    if [ -z "$STATUS" ] && [ -s "$output_path" ] && [ "$FORCE" -eq 0 ]; then
        log_warn "[$run_id] a saída já existe, ignorando (use --force para reprocessar): $output_path"
        STATUS="SKIPPED"
    fi

    if [ -z "$STATUS" ]; then
        nproc_check "$num_workers"
        mkdir -p "$(dirname "$output_path")"

        CMD=(pyscenic grn --num_workers "$num_workers" --output "$output_path" --method "$method")
        [ -n "$seed" ] && CMD+=(--seed "$seed")
        CMD+=("$loom_path" "$tfs_path")

        if [ "$DRY_RUN" -eq 1 ]; then
            log_info "[$run_id] (dry-run) comando: ${CMD[*]}"
            STATUS="DRY_RUN"
        else
            log_info "[$run_id] executando: ${CMD[*]}"
            if run_and_log "$LOGFILE" -- "${CMD[@]}"; then
                if validate_csv_output "$output_path" "TF" "target" "importance"; then
                    STATUS="OK"
                    NEDGES="$VALIDATE_NROWS"
                    log_ok "[$run_id] concluído em ${RUN_ELAPSED_SECONDS}s, $NEDGES conexões (edges) geradas"
                else
                    STATUS="FAIL_OUTPUT"
                fi
            else
                STATUS="FAIL_RUN"
                log_error "[$run_id] 'pyscenic grn' encerrou com erro, veja $LOGFILE"
            fi

            write_run_metadata_json "$METAFILE" \
                run_id "$run_id" status "$STATUS" command "${CMD[*]}" \
                loom_path "$loom_path" tfs_path "$tfs_path" output_path "$output_path" \
                num_workers "$num_workers" method "$method" seed "$seed" \
                n_edges "${NEDGES:-0}" output_size_bytes "$(file_size_bytes "$output_path")" \
                started_at "$RUN_STARTED_AT" finished_at "$RUN_FINISHED_AT" \
                elapsed_seconds "$RUN_ELAPSED_SECONDS" hostname "$(hostname)" log_file "$LOGFILE"
        fi
    fi

    if [[ "$STATUS" == FAIL* ]]; then
        ANY_FAILED=1
    fi

    OUTPUT_SIZE=$(file_size_bytes "$output_path")
    echo "$run_id,$STATUS,$NEDGES,$RUN_ELAPSED_SECONDS,$OUTPUT_SIZE,$num_workers,$method,$seed,$RUN_STARTED_AT,$RUN_FINISHED_AT,$LOGFILE" >> "$SUMMARY_CSV"
done < "$CONFIG_CSV"

echo
log_info "Resumo salvo em: $SUMMARY_CSV"
column -s, -t "$SUMMARY_CSV" 2>/dev/null || cat "$SUMMARY_CSV"

if [ "$ANY_FAILED" -eq 1 ]; then
    log_error "Uma ou mais execuções falharam. Verifique a coluna 'status' no resumo e os logs em $LOGS_DIR/."
    exit 1
fi

log_ok "Todas as execuções foram processadas com sucesso (ou ignoradas por já existirem)."
