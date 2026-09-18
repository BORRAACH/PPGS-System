# pizzeria_system

## graphify

O grafo de conhecimento do projeto fica em `graphify-out/` (`graph.json`, `GRAPH_REPORT.md`, `graph.html`, `manifest.json`, `cache/`).

### Consultas

- Para perguntas sobre arquitetura, dependências ou "quem chama X", consulte o grafo antes de varrer arquivos: `graphify query "<pergunta>"`, `graphify path "A" "B"` ou `graphify explain "X"`.
- Ao citar um fato tirado do grafo, indique o `source_file:linha` do nó.

### Atualização antes de todo commit

Sempre que for criar um ou mais commits (a pedido do usuário), **antes do primeiro `git commit`**:

1. Rode `graphify update .` na raiz do projeto. Só reprocessa arquivos de código, não usa LLM e aproveita o cache.
   - Se o comando recusar reduzir o grafo depois de uma refatoração que removeu código, confirme que a remoção é intencional e rode `graphify update . --force`.
   - Se houver mudanças em docs ou imagens que precisem entrar no grafo, use `/graphify --update`.
2. Confira com `git status --short graphify-out/` o que mudou.
3. Faça o `git add graphify-out/` e inclua essas alterações **no último commit da fila**, para que o grafo represente o estado final do código. Se o commit final for só de código, use um commit próprio no fim: `Atualiza o grafo de conhecimento (graphify-out)`.

### Quando o usuário já rodou `git add .`

O `git add .` do usuário pode ter entrado antes de o grafo ser atualizado. Nesse caso:

1. Rode `graphify update .` normalmente.
2. Rode `git add graphify-out/` de novo para que a versão nova do grafo, e não a antiga, seja a que entra no commit.
3. Trate `graphify-out/` como parte da fila de commits: nunca o deixe de fora nem o misture nos commits de funcionalidade, exceto no último, como descrito acima.
4. Não desfaça o que o usuário já deixou em stage (`git reset`, `git restore --staged`). Só acrescente o grafo atualizado.

### Regras gerais

- `graphify-out/` é versionado no git de propósito; não o adicione ao `.gitignore`.
- Nunca faça `git commit` com o grafo desatualizado em relação ao código que está no commit.
