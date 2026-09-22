# Como Contribuir

Este repositório utiliza o fluxo padrão de branches + Pull Request. A branch `main` é protegida — sem pushes diretos, sem force pushes, e qualquer alteração entra apenas por meio de um PR revisado.

## Fluxo de trabalho

1. Crie uma branch a partir de uma `main` atualizada:

   ```bash
   git switch main && git pull
   git switch -c <tipo>/<descricao-curta>   # ex.: feat/replicate-averaging
   ```

   Prefixos comuns: `feat/`, `fix/`, `refactor/`, `docs/`, `chore/`.

2. Faça suas alterações, seguindo o estilo existente no arquivo em que estiver trabalhando (padrões de nomenclatura, densidade de comentários, convenções de aspas).

3. Antes de abrir um PR, execute localmente o que a CI irá verificar:

   ```bash
   shellcheck scripts/**/*.sh          # ou a extensão de shellcheck do seu editor
   ruff check .
   bash -n scripts/**/*.sh references/*.sh   # verificação básica apenas de sintaxe
   ```

4. Envie as alterações e abra um PR contra a `main`:

   ```bash
   git push -u origin <sua-branch>
   gh pr create --base main --fill      # ou através da interface web do GitHub
   ```

   Preencha o modelo de PR — ele foi elaborado de forma intencionalmente concisa.

5. Um PR precisa de:
   - **1 aprovação** (de um Code Owner, caso sua alteração afete uma área listada em `.github/CODEOWNERS`).
   - **CI aprovada** (shellcheck, ruff e verificação de sintaxe bash).
   - **Todas as discussões de revisão resolvidas.**

6. O método de mesclagem é **Squash and merge** — o histórico de commits da sua branch não precisa ser impecável, mas certifique-se de escrever uma mensagem de commit final clara (ou ajustar a mensagem sugerida no squash), pois é ela que ficará registrada na `main`.

## Notas sobre estilo de código

- Scripts Shell: use `set -uo pipefail` (não `-e`, caso um script processe linhas de forma independente e uma falha individual não deva derrubar toda a execução) e utilize as funções auxiliares de log e tratamento de erros já existentes em `scripts/lib/common.sh`, em vez de recriá-las.
- Python: siga o `ruff.toml` (atualmente com as regras `E`, `F`, `B` e limite de 100 caracteres por linha). Execute `ruff check .` antes de realizar o push.
- Nunca crie ou edite manualmente arquivos `configs/*.local.csv`/`artifacts/**/*.local.csv` — eles são gerados pelo `scripts/generate_configs.py`. Se precisar de um novo exemplo, adicione-o em `artifacts/examples/`.
- Não versione dados reais, credenciais ou caminhos absolutos específicos da sua máquina. Certifique-se de que o `.gitignore` contemple qualquer novo padrão de pastas ou arquivos exclusivamente locais que você adicionar.

## Dúvidas

Abra uma *issue* ou pergunte no canal de comunicação utilizado pela equipe — este documento cobre apenas o fluxo técnico de Git e CI, não decisões sobre o escopo do projeto.