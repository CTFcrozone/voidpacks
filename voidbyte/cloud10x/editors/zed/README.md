# Zed snippets

Snippets for the prompt templates in `../../prompts/`: the parameters and the task, ready to fill in with Tab.

| Prefix | Prompt |
|---|---|
| `c10-scaffold-min` | `scaffold-minimal.md` |
| `c10-scaffold-db` | `scaffold-web-db.md` |
| `c10-service` | `add-service.md` |
| `c10-realm` | `add-realm.md` |
| `c10-audit` | `audit.md` |

Install (merge the entries instead if you already have `markdown.json`):

```sh
P=~/.aipack-base/pack/installed/voidbyte/cloud10x
mkdir -p ~/.config/zed/snippets
cp $P/editors/zed/markdown.json ~/.config/zed/snippets/markdown.json
```

Use: in `.aipack/.prompt/pro@coder/coder-prompt.md`, delete everything from `# PARAMETERS` down to the line above `====`, type the prefix, accept it from the completion menu, and Tab through the parameters. The `====` footer and the YAML block at the top stay as `aip` made them.

The snippets copy the prompt text. After a pack update that changes a prompt, copy the file again.
