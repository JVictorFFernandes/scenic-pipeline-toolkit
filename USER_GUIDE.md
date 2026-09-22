# Guia do Usuário

Um passo a passo para configurar este toolkit em uma máquina Ubuntu recém-instalada e executar sua primeira análise de `pyscenic grn` + `ctx`, do zero. Para uma referência rápida de comandos após a configuração inicial, consulte o [README](README.md).

## 0. Antes de começar

Você precisará de:
- Uma máquina ou VM com Ubuntu (ou baseada em Debian) recém-instalada, com acesso `sudo`.
- Seus próprios dados: uma matriz de expressão (`.loom`), uma lista de fatores de transcrição (FTs) (`.txt`) e bancos de dados de motivos do cisTarget (arquivos `.feather` + `.tbl`) para os FTs que deseja analisar.

Ainda não tem seus próprios dados? Vá direto para o [passo 7](#7-ainda-não-tem-dados-experimente-o-smoke-test) para testar todo o pipeline com pequenos arquivos de referência oficiais primeiro.

## 1. Clonar o repositório

```bash
git clone https://github.com/PLeonLopes/scenic-pipeline-toolkit.git
cd scenic-pipeline-toolkit
```

## 2. Instalar o pyscenic e o pycistarget

```bash
bash scripts/install/install_pyscenic_pycistarget.sh
```

Isso leva alguns minutos na primeira vez (instala o Conda/Mamba caso não estejam instalados e, em seguida, dois ambientes separados). É seguro executar novamente se for interrompido — ele continuará de onde parou.

Confirme se a instalação funcionou:

```bash
bash scripts/install/verify_installation.sh
```

Você deverá ver `Summary: ALL OK.` ao final. Se não, a saída indicará exatamente qual verificação falhou — corrija o problema antes de prosseguir.

A partir de agora, abra um novo terminal (ou execute `source ~/.bashrc`) e ative o ambiente antes de fazer qualquer outra coisa:

```bash
conda activate scenic
```

## 3. Coloque seus dados onde o toolkit possa encontrá-los

Crie uma pasta (qualquer nome, em qualquer local) e coloque os seguintes arquivos dentro dela:
- Sua matriz de expressão `.loom`.
- Seu arquivo `.txt` com a lista de FTs (o nome do arquivo deve conter "tfs", ex.: `hs_hgnc_tfs.txt`).
- Um par `.feather` + `.tbl` **por FT** que você deseja analisar (os dois nomes de arquivo precisam compartilhar o nome do FT — consulte `--help` no próximo passo se os seus não seguirem o padrão de nomenclatura padrão).
- *(Opcional)* um par genérico extra de `.feather` + `.tbl` (não vinculado a nenhum FT específico) se você também quiser uma execução de controle (*baseline*) de `ctx` para todo o genoma.

Exemplo de estrutura:

```
my_data/
├── my_expression.loom
├── my_tfs.txt
├── TF1.genes_vs_motifs.rankings.feather
├── TF1.tbl
├── TF2.genes_vs_motifs.rankings.feather
└── TF2.tbl
```

## 4. Gerar a configuração da execução

Esta é a única etapa de "configuração" — você nunca precisará escrever um CSV manualmente.

```bash
python scripts/generate_configs.py
```

Responda às perguntas interativas (pressione Enter para aceitar o valor padrão entre `[colchetes]`):

```
Folder with your data (loom, TF list, feather/tbl files): my_data
Project name (groups related runs under artifacts/<project>/, e.g. 'canonical_tfs'): my_project
Cell line (optional, e.g. 'HepG2'): HepG2
Run ID (short name for this experiment, e.g. 'my_experiment'): my_first_run
Number of grn replicates (grnboost2 is stochastic; run it several times for robustness) [1]:
Number of workers [4]:
NES threshold (used by ctx) [2.5]:
Dask mode (used by ctx) [dask_multiprocessing]:
GRN method (used by grn) [grnboost2]:
Output folder [artifacts/my_project/hepg2/outs]:
```

Para uma primeira tentativa, basta aceitar todos os valores padrão (pressionando Enter a cada vez), exceto a pasta de dados, o nome do projeto e o ID da execução. No final, o script exibirá o que encontrou e onde gravou as configurações — algo como:

```
Found loom:          my_data/my_expression.loom
Found TF list:       my_data/my_tfs.txt
Found 2 TF(s) with both feather+tbl: TF1, TF2
Artifact folder:     artifacts/my_project/HepG2
Wrote artifacts/my_project/HepG2/configs/grn_runs_2026-01-01_10-30-00.local.csv (1 row(s), seed=1..1 for reproducibility)
Wrote artifacts/my_project/HepG2/configs/ctx_runs_2026-01-01_10-30-00.local.csv (2 rows)
```

`artifacts/<project>/[<cell-line>/]configs/` é uma pasta **estável** — toda vez que você executa este comando, ele adiciona um **novo par de arquivos com timestamp** lá em vez de sobrescrever o anterior, permitindo que você sempre consulte exatamente qual configuração gerou determinado resultado. As pastas irmãs `logs/` e `outs/` são os locais onde os logs e as saídas do pyscenic deste projeto serão salvos após executar `grn`/`ctx` (consulte o [passo 8](#8-onde-estão-os-meus-resultados)) — tudo sobre um projeto permanece junto. Use `--project`/`--cell-line`/`--run-id` (e pule totalmente as perguntas interativas) para automatizar isso via script — consulte o [README](README.md#2-configurando-uma-execução).

Se o script informar que não conseguiu encontrar seus arquivos loom/lista de FTs/feather/tbl, verifique novamente o passo 3 — os nomes dos arquivos devem seguir os padrões descritos lá.

## 5. Executar o `grn`

O passo 4 exibiu os comandos exatos para execução sob "Next steps" — copie o primeiro, que se parece com isto:

```bash
bash scripts/run_pyscenic_grn.sh artifacts/my_project/HepG2/configs/grn_runs_2026-01-01_10-30-00.local.csv
```

Você verá o progresso do `pyscenic` em tempo real na tela. Esta é a etapa mais demorada — para um conjunto de dados real, pode levar de vários minutos a algumas horas, dependendo do tamanho dos dados e da máquina. Quando terminar, você verá um resumo de uma linha por execução e `[ OK ]` se tudo tiver corrido bem.

## 6. Executar o `ctx`

A mesma ideia, utilizando o segundo comando de "Next steps" do passo 4:

```bash
bash scripts/run_pyscenic_ctx.sh artifacts/my_project/HepG2/configs/ctx_runs_2026-01-01_10-30-00.local.csv
```

Uma execução por FT (além do baseline, se houver). Com as configurações padrão, você verá uma barra de progresso ao vivo `[####] | 42% Completed` para cada um.

## 7. Ainda não tem dados? Experimente o smoke test

Antes de ter seus próprios arquivos, você pode validar toda a instalação usando arquivos de referência oficiais menores:

```bash
bash scripts/tests/setup_real_smoke_test.sh
bash scripts/run_pyscenic_grn.sh artifacts/examples/grn_smoke_test.csv
bash scripts/run_pyscenic_ctx.sh artifacts/examples/ctx_smoke_test.csv
```

Isso baixa cerca de 390 MB na primeira vez. Isso comprova que o pipeline roda corretamente de ponta a ponta — não produzirá resultados biologicamente significativos (os dados de expressão são ruído aleatório), servindo apenas como um teste mecânico de funcionamento. Quando tiver dados reais, volte para o [passo 3](#3-coloque-seus-dados-onde-o-toolkit-possa-encontrá-los).

## 8. Onde estão os meus resultados?

Tudo sobre um projeto/linhagem celular — a configuração gerada, o que aconteceu durante a execução e os resultados em si — fica reunido sob uma única pasta `artifacts/<project>/[<cell-line>/]`, dividida em três subpastas irmãs:

```
artifacts/my_project/hepg2/configs/grn_runs_*.local.csv           a configuração gerada (passo 4)
artifacts/my_project/hepg2/configs/ctx_runs_*.local.csv

artifacts/my_project/hepg2/outs/adj/<run_id>.tsv                  um por execução do grn (a rede regulatória)
artifacts/my_project/hepg2/outs/regs/<run_id>/reg_*.csv           um por execução do ctx (os regulons)

artifacts/my_project/hepg2/logs/<grn|ctx>_<run_id>.log            saída completa dessa execução específica
artifacts/my_project/hepg2/logs/<grn|ctx>_summary_*.csv           uma linha por execução: status, tempo, tamanho da saída
artifacts/my_project/hepg2/logs/<grn|ctx>_<run_id>.meta.json      as mesmas informações estruturadas por execução
```

Nada fica em uma pasta global separada de `outs/` ou `logs/` — portanto, abrir a pasta de um projeto/linhagem celular mostra tudo sobre ele: o que você *solicitou* (`configs/`), o que *aconteceu* (`logs/`) e o que *foi gerado* (`outs/`).

## 9. Algo falhou — e agora?

Verifique a coluna `status` na tabela de resumo exibida ao final (também salva na pasta `logs/` ao lado da configuração executada — consulte o [passo 8](#8-onde-estão-os-meus-resultados)). O [README](README.md#6-o-que-fazer-quando-uma-execução-falha) explica o significado de cada status e qual arquivo de log verificar.

## 10. Pronto para escalar?

Assim que uma pequena execução funcionar de ponta a ponta, você pode:
- Apontar o `--data-dir` para o seu conjunto de dados real e completo.
- Adicionar `--replicates 30` (ou quantas desejar) para executar o `grn` várias vezes como teste de robustez — consulte o [README](README.md#2-configurando-uma-execução) para ver o que isso altera.
- Migrar para um servidor dedicado em vez de um laptop — veja a nota sobre memória na seção [Notas](README.md#notas) do README; uma lista real de FTs e um dataset completo podem exigir muito mais memória RAM do que os testes rápidos acima.