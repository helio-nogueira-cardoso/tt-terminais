#!/usr/bin/env bash
# Consistência e completude da documentação que os agentes recebem (skills, README, guia do celular):
#  - cada skill tem frontmatter válido e o nome da pasta onde o tt a instala;
#  - a skill do celular tem seções numeradas em sequência e toda referência "seção N" (dentro dela e vinda de outros
#    documentos) aponta para uma seção que existe;
#  - todo script do celular que o repositório traz (termux/) está citado na skill;
#  - nenhum dado pessoal (máquinas, e-mails, IPs da tailnet) entrou nos documentos de um repositório PÚBLICO.
source "$(dirname "$0")/lib.sh"; isolar

python3 -I - "$RAIZ" <<'FIM_PY' || falhou 'documentação inconsistente (acima)'
import os, re, sys
raiz = sys.argv[1]
erros = []
def ler(rel): return open(os.path.join(raiz, rel), encoding="utf-8").read()

# 1) frontmatter das skills: nome = pasta de instalação, descrição que ajude a decidir quando usar
skills = {"skill-tt-terminais.md": "tt-terminais", "skill-celular-android.md": "celular-android", "skill-rodizio-de-contas.md": "rodizio-de-contas"}
for arq, nome in skills.items():
    t = ler(arq)
    m = re.match(r"---\nname: ([^\n]+)\ndescription: ([^\n]+)\n---\n", t)
    if not m: erros.append(f"{arq}: frontmatter ausente ou fora do formato (--- / name / description / ---)"); continue
    if m.group(1).strip() != nome: erros.append(f"{arq}: name '{m.group(1)}' deveria ser '{nome}' (a pasta onde o tt instala a skill)")
    if len(m.group(2)) < 150: erros.append(f"{arq}: a descrição tem {len(m.group(2))} caracteres; descreva quando usar a skill")

# 2) skill do celular: seções 1..N em sequência; referências "seção N" resolvem
cel = ler("skill-celular-android.md")
nums = [int(n) for n in re.findall(r"(?m)^## (\d+)\. ", cel)]
if nums != list(range(1, len(nums) + 1)): erros.append(f"skill celular-android: seções fora de sequência: {nums}")
maximo = max(nums) if nums else 0
def refs(txt):
    for m in re.finditer(r"(?:seção|seções|Seção)\s+(\d+)(?:\s*(?:a|e|–|-)\s*(\d+))?", txt):
        yield int(m.group(1))
        if m.group(2): yield int(m.group(2))
for n in refs(cel):
    if not 1 <= n <= maximo: erros.append(f"skill celular-android: referência a 'seção {n}', mas só há 1..{maximo}")
# referências vindas de fora: "…celular-android…, seção N" tem de existir e ser a da receita de login quando diz "seção 14"
for arq in ["README.md", "skill-tt-terminais.md", "skill-rodizio-de-contas.md", "termux/ANDROID-ADB.md", "NOVIDADES.md"]:
    for m in re.finditer(r"celular-android[^\n]{0,60}?seção\s+(\d+)", ler(arq)):
        n = int(m.group(1))
        if not 1 <= n <= maximo: erros.append(f"{arq}: aponta para a seção {n} da skill celular-android, que não existe")
        elif n == 14 and "navegador" not in re.search(rf"(?m)^## 14\. ([^\n]+)", cel).group(1).lower():
            erros.append(f"{arq}: a seção 14 da skill celular-android não é mais a do navegador do celular")

# 3) todo script do celular que o repo traz está citado na skill
for rel in sorted(os.listdir(os.path.join(raiz, "termux", "bin"))) + ["celular.sh", "android-ajustes.sh", "atalhos.sh", "boot-tt"]:
    if rel not in cel: erros.append(f"skill celular-android não cita {rel}")

# 4) higiene de repositório público: nada que identifique as máquinas, contas ou a rede de quem desenvolve.
#    Padrões genéricos (IP da tailnet, uid de app do Android) + os nomes PRIVADOS lidos em tempo de execução do perfil de
#    quem roda o teste (máquinas e e-mails cadastrados): assim a própria lista de proibidos nunca entra no repositório.
partes = [r"\b100\.\d{1,3}\.\d{1,3}\.\d{1,3}\b", r"\bu0_a\d{3}\b"]
real = os.environ.get("HOME_REAL", "")
def privados(rel, colunas):
    try: linhas = open(os.path.join(real, ".config", "tt", rel), encoding="utf-8").read().splitlines()
    except OSError: return []
    out = []
    for l in linhas:
        if l.lstrip().startswith("#") or not l.strip(): continue
        campos = l.split("\t") if "\t" in l else l.split()
        for c in colunas:
            if c < len(campos): out.append(campos[c])
    return out
nomes = privados("maquinas", [0, 1]) + privados("contas-ia", [1])  # hosts, usuários e e-mails (o rótulo é palavra comum: "empresa")
for n in nomes:
    n = n.strip()
    if "@" in n: partes += [re.escape(n), re.escape(n.split("@")[0]), re.escape(n.split("@")[1])] if not n.split("@")[1].endswith(("gmail.com", "outlook.com", "hotmail.com")) else [re.escape(n), re.escape(n.split("@")[0])]
    elif len(n) >= 8 and n != "-": partes.append(re.escape(n))  # usuário curto ("helio") aparece em URLs públicas legítimas
proibidos = re.compile("|".join(sorted(set(partes), key=len, reverse=True)), re.I)
docs = ["README.md", "NOVIDADES.md", "AGENTS.md", "AI-DLC.md", "agentes-regras-tt.md", "termux/ANDROID-ADB.md"] + list(skills)
docs += [f"tests/{f}" for f in sorted(os.listdir(os.path.join(raiz, "tests"))) if f.startswith(("test_login_pelo_celular", "test_ia_login", "test_docs"))]
for arq in docs:
    for n, linha in enumerate(ler(arq).splitlines(), 1):
        m = proibidos.search(linha)
        if m: erros.append(f"{arq}:{n}: dado pessoal em repositório público ('{m.group(0)}')")

if erros:
    print("\n".join(erros), file=sys.stderr); sys.exit(1)
print(f"ok: {len(skills)} skills com frontmatter válido; skill do celular com {maximo} seções e referências que resolvem; scripts do celular citados; sem dados pessoais ({len(nomes)} nomes privados conferidos)")
FIM_PY
passou 'documentação consistente (frontmatter, seções, scripts do celular, higiene do repositório público)'
echo "TODOS OS TESTES PASSARAM"
