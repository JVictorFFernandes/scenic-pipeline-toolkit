#!/usr/bin/env python
"""
Gera automaticamente os CSVs de execução do grn/ctx, em vez de escrever
manualmente uma linha para cada FT.

Execute uma vez por experimento/novo lote de dados. Duas formas de uso:

  Interativo (sem argumentos) — pergunta cada valor, com padrões sensatos
  que você pode aceitar apenas pressionando Enter:

    python scripts/generate_configs.py

  Não interativo (passando --data-dir) — para scripts/automação/execuções
  repetidas, pula todas as perguntas:

    python scripts/generate_configs.py --data-dir my_data --project my_project --run-id my_experiment --num-workers 4

O que ele procura dentro da pasta de dados (recursivamente):
  - um arquivo .loom                          -> matriz de expressão
  - um arquivo de lista de FTs *tfs*.txt      -> reguladores candidatos para o grn
  - arquivos .feather que casem com --feather-regex -> um por FT, para o ctx
  - arquivos .tbl que casem com --tbl-regex   -> um por FT, para o ctx

Um FT é incluído no ctx_runs.local.csv apenas se AMBOS os seus arquivos
.feather e .tbl forem encontrados; FTs com apenas um dos dois são ignorados
com um aviso (nada é escrito silenciosamente de forma incorreta).

Se for encontrado exatamente um par extra .feather/.tbl que NÃO corresponda
a nenhum FT (um banco de dados cisTarget genérico, referente ao genoma
inteiro, não vinculado a um único FT), ele é adicionado como uma linha extra
de controle (baseline) "motifs_only" por réplica, executada antes das linhas
por FT — passe --no-baseline para pular isso mesmo que esse par exista.

Passe --replicates N (padrão 1) para executar o grn N vezes de forma
independente (o grnboost2 não tem uma seed aleatória fixa, então cada
execução naturalmente é diferente) e cruzar a adjacência de cada réplica com
todos os FTs para o ctx — ex.: --replicates 30 com 14 FTs gera 30 linhas de
grn e 30*14=420 linhas de ctx.

Cada execução deste script grava um novo par de arquivos com carimbo de
data/hora (timestamp) em uma pasta configs/ estável — nada é sobrescrito, de
modo que o histórico completo de cada configuração gerada permanece em disco
para auditoria. As pastas logs/ e outs/ (adj/, regs/ do próprio pyscenic)
são irmãs dessa pasta configs/, de modo que tudo sobre um
projeto/linhagem celular — o que você pediu, o que aconteceu e o que saiu —
fica reunido sob uma única pasta artifacts/<project>/:

    artifacts/<project>/[<cell-line>/]configs/grn_runs_<timestamp>.local.csv
    artifacts/<project>/[<cell-line>/]configs/ctx_runs_<timestamp>.local.csv
    artifacts/<project>/[<cell-line>/]logs/...
    artifacts/<project>/[<cell-line>/]outs/adj/...
    artifacts/<project>/[<cell-line>/]outs/regs/...

--project agrupa execuções relacionadas (ex.: todo o trabalho com FTs
canônicos); --cell-line é opcional e adiciona mais um nível de agrupamento
(ex.: 'HepG2', 'K562'). Esses arquivos *.local.csv gerados são os que
scripts/run_pyscenic_grn.sh e scripts/run_pyscenic_ctx.sh recebem como
argumento, e toda a árvore artifacts/<project>/ é ignorada pelo Git — ela
contém caminhos reais específicos da máquina e saídas de execuções, nunca
deve ser commitada. artifacts/examples/*.example.csv é algo separado:
modelos rastreados e seguros para compartilhar, usados no smoke test, não
gerados por este script.
"""
import argparse
import csv
import re
import sys
from datetime import datetime
from pathlib import Path

DEFAULT_FEATHER_REGEX = r"motifs_plus_([A-Za-z0-9]+)\.genes_vs_motifs\.rankings\.feather$"
DEFAULT_TBL_REGEX = r"pptf_([A-Za-z0-9]+)\.tbl$"
DEFAULT_TFS_GLOB = "*tfs*.txt"
# Timestamp legível e ainda assim ordenável para nomes de arquivo, ex.: 2026-09-08_21-02-00.
TIMESTAMP_FORMAT = "%Y-%m-%d_%H-%M-%S"


def slugify(value: str) -> str:
    """Torna uma string segura para uso como um único componente de caminho,
    e normaliza a caixa (case) — usado especificamente para
    --project/--cell-line, para que 'HepG2', 'hepg2' e 'HEPG2' caiam todos
    exatamente na mesma pasta em vez de criar silenciosamente três pastas
    diferentes."""
    return re.sub(r"[^A-Za-z0-9_-]+", "_", value.strip()).strip("_").lower()


def scoped_dir(root: str, project: str, cell_line: str | None) -> Path:
    """Uma pasta estável delimitada por projeto (e, opcionalmente, linhagem
    celular) sob `root`: <root>/<project>/[<cell-line>/]. Execuções
    repetidas adicionam novos arquivos de configuração com timestamp ali, em
    vez de novas pastas — e essa mesma pasta também guarda os logs e as
    saídas do pyscenic (adj/, regs/) desse projeto/linhagem celular, de modo
    que tudo sobre um projeto fique em um único lugar."""
    parts = [Path(root), slugify(project)]
    if cell_line:
        parts.append(slugify(cell_line))
    return Path(*parts)


def artifact_dir_for(project: str, cell_line: str | None) -> Path:
    return scoped_dir("artifacts", project, cell_line)


def config_filenames(when: datetime | None = None) -> tuple[str, str]:
    """(nome_arquivo_grn, nome_arquivo_ctx) para uma execução ocorrendo em
    `when` (padrão: agora) — ex.: ('grn_runs_2026-09-08_21-02-00.local.csv',
    'ctx_runs_...')."""
    timestamp = (when or datetime.now()).strftime(TIMESTAMP_FORMAT)
    return f"grn_runs_{timestamp}.local.csv", f"ctx_runs_{timestamp}.local.csv"


def ask(question: str, default: str | None = None, validate=None) -> str:
    """Pede ao usuário um valor, exibindo `default` (usado caso ele apenas
    pressione Enter). Pergunta novamente se `validate(value)` retornar uma
    string de erro."""
    suffix = f" [{default}]" if default is not None else ""
    while True:
        answer = input(f"{question}{suffix}: ").strip()
        if not answer:
            if default is not None:
                answer = default
            else:
                print("  Este valor é obrigatório, por favor informe algo.")
                continue
        if validate:
            error = validate(answer)
            if error:
                print(f"  {error}")
                continue
        return answer


def run_interactive() -> argparse.Namespace:
    print("=== scenic-pipeline-toolkit: configuração interativa ===")
    print("Pressione Enter para aceitar o padrão exibido entre [colchetes].\n")

    data_dir = ask(
        "Pasta com seus dados (loom, lista de FTs, arquivos feather/tbl)",
        validate=lambda v: None if Path(v).is_dir() else f"'{v}' não é um diretório, tente novamente.",
    )
    project = ask("Nome do projeto (agrupa execuções relacionadas em artifacts/<project>/, ex.: 'canonical_tfs')")
    cell_line = input("Linhagem celular (opcional, ex.: 'HepG2'): ").strip() or None
    run_id = ask("ID da execução (nome curto para este experimento, ex.: 'my_experiment')")
    replicates = ask(
        "Número de réplicas do grn (o grnboost2 é estocástico; execute várias vezes para robustez)",
        default="1",
        validate=lambda v: None if v.isdigit() and int(v) > 0 else "Deve ser um número inteiro positivo.",
    )
    num_workers = ask(
        "Número de workers",
        default="4",
        validate=lambda v: None if v.isdigit() and int(v) > 0 else "Deve ser um número inteiro positivo.",
    )
    nes_threshold = ask("Limiar de NES (usado pelo ctx)", default="2.5")
    mode = ask("Modo do Dask (usado pelo ctx)", default="dask_multiprocessing")
    method = ask("Método de GRN (usado pelo grn)", default="grnboost2")
    outs_dir = ask("Pasta de saída", default=str(artifact_dir_for(project, cell_line) / "outs"))

    return argparse.Namespace(
        data_dir=data_dir,
        project=project,
        cell_line=cell_line,
        run_id=run_id,
        replicates=int(replicates),
        no_seed=False,
        num_workers=int(num_workers),
        nes_threshold=nes_threshold,
        mode=mode,
        method=method,
        outs_dir=outs_dir,
        loom=None,
        tfs=None,
        baseline_feather=None,
        baseline_tbl=None,
        no_baseline=False,
        feather_regex=DEFAULT_FEATHER_REGEX,
        tbl_regex=DEFAULT_TBL_REGEX,
        grn_csv=None,
        ctx_csv=None,
    )


def find_one(data_dir: Path, pattern: str, kind: str, override: str | None) -> Path:
    if override:
        path = Path(override)
        if not path.is_file():
            sys.exit(f"ERRO: --{kind.lower().replace(' ', '-')} aponta para um arquivo que não existe: {path}")
        return path

    matches = sorted(data_dir.rglob(pattern))
    if len(matches) == 1:
        return matches[0]
    if len(matches) == 0:
        sys.exit(
            f"ERRO: nenhum {kind} encontrado em {data_dir} (procurado por '{pattern}'). "
            f"Informe-o explicitamente com a flag correspondente."
        )
    sys.exit(
        f"ERRO: encontrados {len(matches)} possíveis arquivos {kind} em {data_dir}, esperava-se exatamente um:\n  "
        + "\n  ".join(str(m) for m in matches)
        + "\nInforme o correto explicitamente com a flag correspondente."
    )


def find_tf_files(data_dir: Path, extension: str, regex: str) -> dict[str, Path]:
    pattern = re.compile(regex)
    found: dict[str, Path] = {}
    for path in sorted(data_dir.rglob(f"*.{extension}")):
        m = pattern.search(path.name)
        if m:
            found[m.group(1)] = path
    return found


def find_baseline(data_dir: Path, extension: str, matched: set[Path], kind: str, override: str | None) -> Path | None:
    """Encontra o feather/tbl genérico, referente ao genoma inteiro (o que
    NÃO é um dos arquivos por FT já encontrados por find_tf_files). Retorna
    None se não houver exatamente um arquivo desse tipo e nenhum override
    tiver sido informado — uma linha de baseline é opcional, então isso
    nunca encerra o programa."""
    if override:
        path = Path(override)
        if not path.is_file():
            sys.exit(f"ERRO: --{kind} aponta para um arquivo que não existe: {path}")
        return path

    candidates = [p for p in sorted(data_dir.rglob(f"*.{extension}")) if p not in matched]
    if len(candidates) == 1:
        return candidates[0]
    if len(candidates) > 1:
        print(
            f"AVISO: encontrado(s) {len(candidates)} arquivo(s) .{extension} não vinculado(s) a nenhum FT, "
            f"esperava-se no máximo um para o baseline 'motifs_only' — ignorando. "
            f"Passe --{kind} para escolher um explicitamente:\n  " + "\n  ".join(str(c) for c in candidates),
            file=sys.stderr,
        )
    return None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--data-dir",
        help="pasta a ser varrida em busca de arquivos loom/lista de FTs/feather/tbl. "
        "Omita esta flag (e todas as outras) para ser guiado interativamente.",
    )
    parser.add_argument(
        "--project",
        help="agrupa execuções relacionadas em artifacts/<project>/ (ex.: 'canonical_tfs'). "
        "Obrigatório junto com --data-dir no modo não interativo.",
    )
    parser.add_argument("--cell-line", help="opcional, ex.: 'HepG2' — incluído no nome da pasta da execução")
    parser.add_argument("--run-id", help="nome curto para este experimento, ex.: 'my_experiment'")
    parser.add_argument(
        "--replicates",
        type=int,
        default=1,
        help="número de execuções independentes do grn (padrão: 1). Cada réplica é cruzada com todos os FTs para o ctx.",
    )
    parser.add_argument(
        "--no-seed",
        action="store_true",
        help="não atribui um --seed ao grn (padrão: a réplica i recebe seed=i, para que as execuções sejam "
        "reprodutíveis e ainda assim independentes entre si; passe esta flag para usar a seed aleatória "
        "padrão do próprio pyscenic a cada execução).",
    )
    parser.add_argument("--num-workers", type=int, default=4, help="--num_workers tanto para o grn quanto para o ctx (padrão: 4)")
    parser.add_argument("--nes-threshold", default="2.5", help="--nes_threshold para o ctx (padrão: 2.5)")
    parser.add_argument("--mode", default="dask_multiprocessing", help="--mode para o ctx (padrão: dask_multiprocessing)")
    parser.add_argument("--method", default="grnboost2", help="--method para o grn (padrão: grnboost2)")
    parser.add_argument(
        "--outs-dir",
        help="pasta de saída base para as próprias saídas do pyscenic, adj/ e regs/ "
        "(padrão: artifacts/<project>/[<cell-line>/]outs/ — uma irmã de configs/ e "
        "logs/ desse projeto, para que tudo sobre ele fique reunido)",
    )
    parser.add_argument("--loom", help="override: caminho exato para o arquivo .loom (pula a descoberta automática)")
    parser.add_argument("--tfs", help="override: caminho exato para o arquivo .txt com a lista de FTs (pula a descoberta automática)")
    parser.add_argument("--baseline-feather", help="override: caminho exato para o .feather genérico, referente ao genoma inteiro (pula a descoberta automática)")
    parser.add_argument("--baseline-tbl", help="override: caminho exato para o .tbl genérico, referente ao genoma inteiro (pula a descoberta automática)")
    parser.add_argument(
        "--no-baseline",
        action="store_true",
        help="não adiciona uma linha de baseline 'motifs_only', mesmo se um par feather+tbl referente ao genoma inteiro for encontrado",
    )
    parser.add_argument(
        "--feather-regex",
        default=DEFAULT_FEATHER_REGEX,
        help=r"regex com um grupo de captura para o nome do FT, aplicada aos nomes de arquivo .feather "
        rf"(padrão: {DEFAULT_FEATHER_REGEX!r})",
    )
    parser.add_argument(
        "--tbl-regex",
        default=DEFAULT_TBL_REGEX,
        help=rf"regex com um grupo de captura para o nome do FT, aplicada aos nomes de arquivo .tbl (padrão: {DEFAULT_TBL_REGEX!r})",
    )
    parser.add_argument("--grn-csv", help="override: caminho de saída exato para o CSV do grn (ignora a estrutura artifacts/<project>/<timestamp>/)")
    parser.add_argument("--ctx-csv", help="override: caminho de saída exato para o CSV do ctx (ignora a estrutura artifacts/<project>/<timestamp>/)")
    args = parser.parse_args()

    if args.data_dir is None:
        if not sys.stdin.isatty():
            parser.error("--data-dir é obrigatório quando não executado em um terminal interativo.")
        args = run_interactive()
    else:
        if args.run_id is None:
            parser.error("--run-id é obrigatório (ou omita --data-dir também, para usar o modo interativo).")
        if args.project is None:
            parser.error("--project é obrigatório (ou omita --data-dir também, para usar o modo interativo).")
        if args.outs_dir is None:
            args.outs_dir = str(artifact_dir_for(args.project, args.cell_line) / "outs")

    if args.replicates < 1:
        parser.error("--replicates deve ser um número inteiro positivo.")

    return args


def replicate_run_ids(run_id: str, replicates: int) -> list[str]:
    """Retorna o run_id de cada réplica. Com replicates=1, o run_id puro é
    usado sem alterações (para que os nomes de arquivo de saída de uma
    única réplica não mudem); com mais réplicas, cada uma recebe um sufixo
    '_repNN' com zeros à esquerda."""
    if replicates == 1:
        return [run_id]
    width = max(2, len(str(replicates)))
    return [f"{run_id}_rep{i:0{width}d}" for i in range(1, replicates + 1)]


def main():
    args = parse_args()

    data_dir = Path(args.data_dir)
    if not data_dir.is_dir():
        sys.exit(f"ERRO: --data-dir não é um diretório: {data_dir}")

    loom_path = find_one(data_dir, "*.loom", "loom", args.loom)
    tfs_path = find_one(data_dir, DEFAULT_TFS_GLOB, "lista de FTs", args.tfs)

    feather_by_tf = find_tf_files(data_dir, "feather", args.feather_regex)
    tbl_by_tf = find_tf_files(data_dir, "tbl", args.tbl_regex)

    tfs_with_both = sorted(set(feather_by_tf) & set(tbl_by_tf))
    feather_only = sorted(set(feather_by_tf) - set(tbl_by_tf))
    tbl_only = sorted(set(tbl_by_tf) - set(feather_by_tf))

    if feather_only:
        print(f"AVISO: {len(feather_only)} FT(s) têm um .feather mas nenhum .tbl correspondente, ignorando: {', '.join(feather_only)}", file=sys.stderr)
    if tbl_only:
        print(f"AVISO: {len(tbl_only)} FT(s) têm um .tbl mas nenhum .feather correspondente, ignorando: {', '.join(tbl_only)}", file=sys.stderr)
    if not tfs_with_both:
        sys.exit("ERRO: nenhum FT tem tanto um arquivo .feather quanto um .tbl — nada a escrever em ctx_runs.local.csv.")

    baseline_feather = None
    baseline_tbl = None
    if not args.no_baseline:
        baseline_feather = find_baseline(data_dir, "feather", set(feather_by_tf.values()), "baseline-feather", args.baseline_feather)
        baseline_tbl = find_baseline(data_dir, "tbl", set(tbl_by_tf.values()), "baseline-tbl", args.baseline_tbl)
        if baseline_feather and not baseline_tbl:
            print(f"AVISO: encontrado um .feather de baseline ({baseline_feather}) mas nenhum .tbl de baseline — ignorando a linha 'motifs_only'.", file=sys.stderr)
            baseline_feather = None
        elif baseline_tbl and not baseline_feather:
            print(f"AVISO: encontrado um .tbl de baseline ({baseline_tbl}) mas nenhum .feather de baseline — ignorando a linha 'motifs_only'.", file=sys.stderr)
            baseline_tbl = None

    print(f"\nLoom encontrado:              {loom_path}")
    print(f"Lista de FTs encontrada:      {tfs_path}")
    print(f"Encontrado(s) {len(tfs_with_both)} FT(s) com feather+tbl: {', '.join(tfs_with_both)}")
    if baseline_feather:
        print(f"Baseline (motifs_only) feather+tbl encontrado: {baseline_feather.name} + {baseline_tbl.name}")

    rep_ids = replicate_run_ids(args.run_id, args.replicates)
    if args.replicates > 1:
        print(f"Gerando {args.replicates} réplica(s) do grn: {', '.join(rep_ids)}")

    # Cada execução adiciona um novo par de arquivos com timestamp a uma
    # pasta estável por projeto (opcionalmente por linhagem celular) —
    # nada é sobrescrito, então artifacts/<project>/configs/ acumula um
    # histórico completo e auditável ao longo do tempo. logs/ e outs/ (via
    # o padrão de --outs-dir, acima) são irmãs de configs/ sob essa mesma
    # pasta de projeto/linhagem celular, para que tudo sobre um projeto
    # fique reunido. --grn-csv/--ctx-csv (se informados) sobrescrevem isso
    # completamente, para casos excepcionais.
    if args.project:
        artifact_dir = artifact_dir_for(args.project, args.cell_line)
        config_dir = artifact_dir / "configs"
        grn_filename, ctx_filename = config_filenames()
        grn_csv_path = Path(args.grn_csv) if args.grn_csv else config_dir / grn_filename
        ctx_csv_path = Path(args.ctx_csv) if args.ctx_csv else config_dir / ctx_filename
        print(f"Pasta de artefatos:  {artifact_dir}")
    else:
        grn_csv_path = Path(args.grn_csv)
        ctx_csv_path = Path(args.ctx_csv)

    grn_csv_path.parent.mkdir(parents=True, exist_ok=True)
    with open(grn_csv_path, "w", newline="") as fh:
        # lineterminator="\n": csv.writer usa por padrão o dialeto 'excel',
        # que sempre grava "\r\n" independentemente do newline="" do
        # open() — esse \r à direita ficaria grudado no último campo de
        # cada linha (aqui, seed) ao ser lido pelo `IFS=',' read` do bash,
        # corrompendo-o.
        writer = csv.writer(fh, lineterminator="\n")
        writer.writerow(["run_id", "loom_path", "tfs_path", "output_path", "num_workers", "method", "seed"])
        for i, rep_id in enumerate(rep_ids, start=1):
            grn_output = f"{args.outs_dir}/adj/{rep_id}.tsv"
            seed = "" if args.no_seed else i
            writer.writerow([rep_id, loom_path, tfs_path, grn_output, args.num_workers, args.method, seed])
    if args.no_seed:
        print(f"Gravado {grn_csv_path} ({len(rep_ids)} linha(s), sem seed — cada execução usará a própria seed aleatória do pyscenic)")
    else:
        print(f"Gravado {grn_csv_path} ({len(rep_ids)} linha(s), seed=1..{len(rep_ids)} para reprodutibilidade)")

    ctx_csv_path.parent.mkdir(parents=True, exist_ok=True)
    n_ctx_rows = 0
    with open(ctx_csv_path, "w", newline="") as fh:
        # Mesma correção do CSV do grn acima — caso contrário, um \r à
        # direita corrompe o último campo de cada linha (aqui, output_path).
        writer = csv.writer(fh, lineterminator="\n")
        writer.writerow(
            ["run_id", "tf_name", "adj_path", "feather_path", "tbl_path", "loom_path", "nes_threshold", "mode", "num_workers", "output_path"]
        )
        for rep_id in rep_ids:
            grn_output = f"{args.outs_dir}/adj/{rep_id}.tsv"

            if baseline_feather:
                row_id = f"{rep_id}_motifs_only"
                output_path = f"{args.outs_dir}/regs/{rep_id}/reg_motifs_only.csv"
                writer.writerow(
                    [row_id, "ALL", grn_output, baseline_feather, baseline_tbl, loom_path, args.nes_threshold, args.mode, args.num_workers, output_path]
                )
                n_ctx_rows += 1

            for tf in tfs_with_both:
                row_id = f"{rep_id}_{tf}"
                output_path = f"{args.outs_dir}/regs/{rep_id}/reg_{tf}.csv"
                writer.writerow(
                    [row_id, tf, grn_output, feather_by_tf[tf], tbl_by_tf[tf], loom_path, args.nes_threshold, args.mode, args.num_workers, output_path]
                )
                n_ctx_rows += 1
    print(f"Gravado {ctx_csv_path} ({n_ctx_rows} linhas)")

    print()
    print("Próximos passos:")
    print(f"    bash scripts/run_pyscenic_grn.sh {grn_csv_path}")
    print(f"    bash scripts/run_pyscenic_ctx.sh {ctx_csv_path}")


if __name__ == "__main__":
    main()
