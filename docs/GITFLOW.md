# Fluxo de versionamento (gitflow)

O OpenFrame segue o modelo gitflow. A regra principal: **a `main` é sempre a
versão mais atual e sem bugs conhecidos**. Nada é commitado direto nela nem na
`develop`; as duas só recebem merges.

## Branches

| Branch | Sai de | Volta para | Para quê |
|---|---|---|---|
| `main` | — | — | Versões publicadas. Cada merge nela ganha uma tag `vX.Y.Z`. |
| `develop` | `main` | — | Integração: o que está pronto para a próxima versão. |
| `feature/<nome>` | `develop` | `develop` | Uma funcionalidade nova. |
| `bugfix/<nome>` | `develop` | `develop` | Correção de um bug que ainda não chegou à `main`. |
| `release/<versão>` | `develop` | `main` e `develop` | Preparar uma versão: só ajustes finais, versão e notas. |
| `hotfix/<versão>` | `main` | `main` e `develop` | Correção urgente de um bug que já está na `main`. |

Nomes em minúsculas, com hífen: `feature/forma-de-onda`, `bugfix/trim-negativo`,
`release/0.2.0`, `hotfix/0.1.1`.

## Comandos

Ativar a proteção depois de clonar (bloqueia commits diretos em `main` e `develop`):

```bash
./scripts/setup-git.sh
```

### Feature ou bugfix

```bash
git switch develop && git pull
git switch -c feature/<nome>
# ...commits...
./scripts/test.sh                      # os testes precisam passar
git switch develop
git merge --no-ff feature/<nome>
git branch -d feature/<nome>
git push origin develop
```

### Release

```bash
git switch -c release/0.2.0 develop
# atualizar CFBundleShortVersionString/CFBundleVersion em scripts/make-app.sh
# e as notas da versão; só correções pequenas daqui em diante
./scripts/test.sh && ./scripts/make-app.sh
git switch main    && git merge --no-ff release/0.2.0 && git tag -a v0.2.0 -m "OpenFrame 0.2.0"
git switch develop && git merge --no-ff release/0.2.0
git branch -d release/0.2.0
git push origin main develop --tags
```

### Hotfix

```bash
git switch -c hotfix/0.2.1 main
# corrigir, testar e atualizar a versão em scripts/make-app.sh
git switch main    && git merge --no-ff hotfix/0.2.1 && git tag -a v0.2.1 -m "OpenFrame 0.2.1"
git switch develop && git merge --no-ff hotfix/0.2.1
git branch -d hotfix/0.2.1
git push origin main develop --tags
```

## Regras

- `./scripts/test.sh` passa antes de qualquer merge.
- Merges sempre com `--no-ff`, para o histórico mostrar cada feature como um bloco.
- Versões no formato semântico `MAJOR.MINOR.PATCH`: feature → MINOR, hotfix → PATCH.
- Mensagens de commit no padrão convencional, em português:
  `feat:`, `fix:`, `refactor:`, `style:`, `docs:`, `test:`, `chore:`.
- O hook de `.githooks/pre-commit` pode ser pulado com `--no-verify`, só em emergência.
