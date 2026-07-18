# update-script

Script único para atualizar tudo em uma máquina Linux (testado em Ubuntu 24.04): sistema,
gerenciadores de pacotes e aplicativos instalados por `.deb`/installer manual que não recebem
atualização automática.

## O que atualiza

Cada passo só roda se a ferramenta correspondente estiver instalada; caso contrário é marcado
como `PULADO` no resumo e o script continua. Isso o torna portável entre máquinas diferentes.

- Sistema: `nala` (com `--full`) ou `apt` como fallback
- Flatpak, Snap, Homebrew
- `asdf` (plugins) + relatório de versões disponíveis
- `rustup`, `uv tools`, Oh My Zsh
- Apps `.deb`/installer sem repositório, com checagem de versão antes de baixar:
  Discord, Docker Desktop, Bruno, Insomnia, Calibre, AWS CLI

## Uso

```bash
./update_all_script.sh            # atualiza tudo
./update_all_script.sh --clean    # + limpeza (autoremove, flatpak/snap/brew cleanup)
./update_all_script.sh --firmware # + atualização de firmware (fwupd)
./update_all_script.sh --help
```

A senha do `sudo` é pedida uma vez no início e mantida viva durante a execução. Ao final,
um resumo mostra `OK` / `FALHOU` / `PULADO` por passo, com a duração de cada um.
