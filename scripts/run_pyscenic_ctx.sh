#!/bin/bash
#
# Executa "pyscenic ctx" para cada linha de um CSV de configuração (um FT por
# linha), com validação de entrada/saída, log por execução e um resumo final.
#
# Uso:
#   bash scripts/run_pyscenic_ctx.sh [config.csv] [--dry-run] [--force] [--quiet]
#
#   config.csv   caminho do CSV (padrão: artifacts/ctx_runs.local.csv — gere-o
#                com scripts/generate_configs.py, não o escreva manualmente)
#   --dry-run    apenas valida os caminhos e imprime o comando, sem chamar o pyscenic
#   --force      reprocessa execuções mesmo se output_path já existir
#   --quiet      não transmite a saída do pyscenic ao vivo, apenas no arquivo de log (bom para nohup/cron)
#
# CSV esperado (com cabeçalho), colunas:
#   run_id,tf_name,adj_path,feather_path,tbl_path,loom_path,nes_threshold,mode,num_workers,output_path
#
set -uo pipefail  # sem -e: cada linha do CSV é tratada individualmente

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

CONFIG_CSV="artifacts/ctx_runs.local.csv"
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
SUMMARY_CSV="$LOGS_DIR/ctx_summary_${TIMESTAMP}.csv"
echo "run_id,tf_name,status,n_regulons,elapsed_seconds,output_size_bytes,num_workers,nes_threshold,mode,started_at,finished_at,log_file" > "$SUMMARY_CSV"

# Total de linhas de dados, para o indicador de progresso "[i/N]" abaixo.
TOTAL_ROWS=$(tail -n +2 "$CONFIG_CSV" | grep -c '[^[:space:]]')

log_info "Usando configuração: $CONFIG_CSV ($TOTAL_ROWS execução(ões))"
[ "$DRY_RUN" -eq 1 ] && log_warn "modo --dry-run: nenhum comando pyscenic será executado de fato."

ANY_FAILED=0
ROW_NUM=0

while IFS=',' read -r run_id tf_name adj_path feather_path tbl_path loom_path nes_threshold mode num_workers output_path || [ -n "$run_id" ]; do
    ROW_NUM=$((ROW_NUM + 1))
    [ "$ROW_NUM" -eq 1 ] && continue  # pula o cabeçalho
    [ -z "$run_id" ] && continue      # pula linhas em branco

    echo
    log_info "=== [$((ROW_NUM - 1))/$TOTAL_ROWS] [$run_id] Executando $tf_name ==="

    LOGFILE="$LOGS_DIR/ctx_${run_id}.log"
    METAFILE="$LOGS_DIR/ctx_${run_id}.meta.json"
    STATUS=""
    NREGULONS=""
    RUN_ELAPSED_SECONDS=0
    RUN_STARTED_AT=""
    RUN_FINISHED_AT=""

    for pair in "adj_path:$adj_path" "feather_path:$feather_path" "tbl_path:$tbl_path" "loom_path:$loom_path"; do
        field="${pair%%:*}"; value="${pair#*:}"
        if [ -z "$STATUS" ] && ! require_file "$value" "[$run_id] $field"; then
            STATUS="FAIL_INPUT"
        fi
    done

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

        CMD=(pyscenic ctx "$adj_path" "$feather_path"
             --annotations_fname "$tbl_path"
             --expression_mtx_fname "$loom_path"
             --nes_threshold "$nes_threshold"
             --mode "$mode"
             --output "$output_path"
             --num_workers "$num_workers"
             --mask_dropouts)

        if [ "$DRY_RUN" -eq 1 ]; then
            log_info "[$run_id] (dry-run) comando: ${CMD[*]}"
            STATUS="DRY_RUN"
        else
            log_info "[$run_id] executando: ${CMD[*]}"
            if run_and_log "$LOGFILE" -- "${CMD[@]}"; then
                if validate_csv_output "$output_path" "TF" "MotifID" "AUC"; then
                    STATUS="OK"
                    NREGULONS="$VALIDATE_NROWS"
                    log_ok "[$run_id] concluído em ${RUN_ELAPSED_SECONDS}s, $NREGULONS linhas geradas"
                else
                    STATUS="FAIL_OUTPUT"
                fi
            else
                STATUS="FAIL_RUN"
                log_error "[$run_id] 'pyscenic ctx' encerrou com erro, veja $LOGFILE"
            fi

            write_run_metadata_json "$METAFILE" \
                run_id "$run_id" tf_name "$tf_name" status "$STATUS" command "${CMD[*]}" \
                adj_path "$adj_path" feather_path "$feather_path" tbl_path "$tbl_path" loom_path "$loom_path" \
                num_workers "$num_workers" nes_threshold "$nes_threshold" mode "$mode" output_path "$output_path" \
                n_regulons "${NREGULONS:-0}" output_size_bytes "$(file_size_bytes "$output_path")" \
                started_at "$RUN_STARTED_AT" finished_at "$RUN_FINISHED_AT" \
                elapsed_seconds "$RUN_ELAPSED_SECONDS" hostname "$(hostname)" log_file "$LOGFILE"
        fi
    fi

    if [[ "$STATUS" == FAIL* ]]; then
        ANY_FAILED=1
    fi

    OUTPUT_SIZE=$(file_size_bytes "$output_path")
    echo "$run_id,$tf_name,$STATUS,$NREGULONS,$RUN_ELAPSED_SECONDS,$OUTPUT_SIZE,$num_workers,$nes_threshold,$mode,$RUN_STARTED_AT,$RUN_FINISHED_AT,$LOGFILE" >> "$SUMMARY_CSV"
done < "$CONFIG_CSV"

echo
log_info "Resumo salvo em: $SUMMARY_CSV"
column -s, -t "$SUMMARY_CSV" 2>/dev/null || cat "$SUMMARY_CSV"

if [ "$ANY_FAILED" -eq 1 ]; then
    log_error "Uma ou mais execuções falharam. Verifique a coluna 'status' no resumo e os logs em $LOGS_DIR/."
    exit 1
fi

log_ok "Todas as execuções foram processadas com sucesso (ou ignoradas por já existirem)."
