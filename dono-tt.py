#!/usr/bin/env python3
# dono-tt.py — o "token de dono" do tt: uma chave de assinatura que só o dono tem. Cada tt traz a parte pública
# (`dono-chaves`, formato allowed_signers do OpenSSH) e só aceita conteúdo do dono se a assinatura confere.
#
#   tt --dono chave [gerar [--no-repo]]   mostra a impressão digital; `gerar` cria ~/.secrets/tt-dono (só uma vez)
#   tt --dono assinar ARQ                 grava ARQ.sig (namespace tt-dono)
#   tt --dono verificar ARQ [ARQ.sig]     confere pelas chaves do pacote (sai 0 se confere)
#   tt --dono estado                      chave privada aqui? chaves aceitas, manifestos do pacote
#   tt --dono biblioteca …                biblioteca padrão (leitor-tt.py biblioteca-padrao)
#
# Só stdlib e `ssh-keygen` (o mesmo do ssh que o tt já exige). A chave privada nunca é copiada, impressa nem sincronizada.
import os
import subprocess
import sys
import tempfile

AQUI = os.path.dirname(os.path.abspath(__file__))
NS = "tt-dono"
IDENT = "dono"


class Erro(Exception):
    pass


def _teste():
    return os.environ.get("TT_DONO_TESTE") == "1"


def arquivo_chaves():
    """Chaves públicas aceitas (allowed_signers). Só o pacote, salvo nos testes."""
    if _teste() and os.environ.get("TT_DONO_CHAVES"):
        return os.environ["TT_DONO_CHAVES"]
    return os.path.join(AQUI, "dono-chaves")


def arquivo_chave_privada():
    if _teste() and os.environ.get("TT_DONO_CHAVE"):
        return os.environ["TT_DONO_CHAVE"]
    return os.path.join(os.path.expanduser("~"), ".secrets", "tt-dono")


def _ssh_keygen(args, entrada=None):
    try:
        return subprocess.run(["ssh-keygen"] + args, input=entrada, capture_output=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise Erro("ssh-keygen indisponível: %s" % e)


def chaves_aceitas():
    """Linhas válidas do dono-chaves."""
    try:
        with open(arquivo_chaves(), encoding="utf-8") as f:
            return [l.strip() for l in f if l.strip() and not l.lstrip().startswith("#")]
    except OSError:
        return []


def verificar_bytes(dados, assinatura):
    """(ok, motivo): `assinatura` (texto da .sig) confere com `dados` por alguma chave do pacote."""
    if not chaves_aceitas():
        return False, "pacote sem chaves do dono (dono-chaves)"
    with tempfile.TemporaryDirectory(prefix="tt-dono-") as d:
        sig = os.path.join(d, "x.sig")
        with open(sig, "wb") as f:
            f.write(assinatura if isinstance(assinatura, bytes) else assinatura.encode())
        try:
            r = _ssh_keygen(["-Y", "verify", "-f", arquivo_chaves(), "-I", IDENT, "-n", NS, "-s", sig], dados)
        except Erro as e:
            return False, str(e)
    if r.returncode == 0:
        return True, "ok"
    linhas = (r.stderr or r.stdout).decode("utf-8", "replace").strip().splitlines()
    return False, linhas[-1] if linhas else "assinatura não confere"


def verificar_arquivo(caminho, sig=None):
    try:
        with open(caminho, "rb") as f:
            dados = f.read()
        with open(sig or caminho + ".sig", "rb") as f:
            assinatura = f.read()
    except OSError as e:
        return False, "sem arquivo ou assinatura: %s" % e.filename
    return verificar_bytes(dados, assinatura)


def assinar_arquivo(caminho):
    chave = arquivo_chave_privada()
    if not os.path.isfile(chave):
        raise Erro("este tt não tem a chave do dono (%s)" % chave.replace(os.path.expanduser("~"), "~"))
    if os.stat(chave).st_mode & 0o077:
        raise Erro("a chave do dono precisa de permissão 600: chmod 600 %s" % chave)
    sig = caminho + ".sig"
    if os.path.exists(sig):
        os.unlink(sig)
    r = _ssh_keygen(["-Y", "sign", "-f", chave, "-n", NS, caminho])
    if r.returncode != 0 or not os.path.isfile(sig):
        raise Erro("não consegui assinar: %s" % (r.stderr or r.stdout).decode("utf-8", "replace").strip())
    ok, motivo = verificar_arquivo(caminho)
    if not ok:
        os.unlink(sig)
        raise Erro("assinei, mas a chave do dono não está em dono-chaves (%s): coloque a pública lá e publique" % motivo)
    return sig


def impressao(pub):
    r = _ssh_keygen(["-l", "-f", pub])
    return r.stdout.decode().strip() if r.returncode == 0 else ""


def cmd_chave(args):
    chave = arquivo_chave_privada()
    pub = chave + ".pub"
    if args and args[0] == "gerar":
        if os.path.exists(chave) or os.path.exists(pub):
            raise Erro("já existe uma chave do dono em %s (não sobrescrevo)" % chave.replace(os.path.expanduser("~"), "~"))
        os.makedirs(os.path.dirname(chave), mode=0o700, exist_ok=True)
        r = _ssh_keygen(["-q", "-t", "ed25519", "-N", "", "-C", "tt-dono", "-f", chave])
        if r.returncode != 0:
            raise Erro("ssh-keygen falhou: %s" % r.stderr.decode("utf-8", "replace").strip())
        os.chmod(chave, 0o600)
        with open(pub, encoding="utf-8") as f:
            partes = f.read().split()
        linha = '%s namespaces="%s" %s %s' % (IDENT, NS, partes[0], partes[1])
        print("chave do dono criada em %s (privada, modo 600; faça backup no seu cofre, ela não vai para o Git)" %
              chave.replace(os.path.expanduser("~"), "~"))
        print(impressao(pub))
        if "--no-repo" in args:
            repo = os.environ.get("TT_REPO") or ""
            alvo = os.path.join(repo, "dono-chaves")
            if not repo or not os.path.isdir(repo):
                raise Erro("sem clone de desenvolvimento (repo=) para gravar dono-chaves")
            with open(alvo, "a", encoding="utf-8") as f:
                f.write(linha + "\n")
            print("chave pública acrescentada a %s: grave e publique para os outros tt a aceitarem" % alvo)
        else:
            print("linha para o dono-chaves do pacote:\n" + linha)
        return 0
    if not os.path.isfile(pub):
        print("este tt não tem a chave do dono (tt --dono chave gerar)")
        return 1
    print(impressao(pub))
    return 0


def cmd_estado(_args):
    chave = arquivo_chave_privada()
    tem = os.path.isfile(chave)
    print("chave do dono neste tt: %s" % ("sim (%s)" % chave.replace(os.path.expanduser("~"), "~") if tem else "não"))
    aceitas = chaves_aceitas()
    print("chaves aceitas pelo pacote: %d" % len(aceitas))
    for l in aceitas:
        with tempfile.NamedTemporaryFile("w", suffix=".pub", delete=False) as t:
            p = l.split()
            t.write("%s %s\n" % (p[-2], p[-1]) if len(p) >= 3 else l + "\n")
        try:
            print("  " + (impressao(t.name) or "(linha ilegível)"))
        finally:
            os.unlink(t.name)
    for nome in ("biblioteca-padrao.json",):
        c = os.path.join(AQUI, nome)
        if os.path.isfile(c):
            ok, motivo = verificar_arquivo(c)
            print("%s: %s" % (nome, "assinatura confere" if ok else "ASSINATURA NÃO CONFERE (%s): ignorado" % motivo))
    return 0


def principal(argv):
    cmd = argv[0] if argv else "estado"
    args = argv[1:]
    if cmd in ("-h", "--help", "ajuda"):
        with open(__file__, encoding="utf-8") as f:
            print("".join(l[2:] for l in f.read().split("import ", 1)[0].splitlines(True)[1:] if l.startswith("#")), end="")
        return 0
    if cmd == "chave":
        return cmd_chave(args)
    if cmd == "estado":
        return cmd_estado(args)
    if cmd == "assinar":
        if not args:
            raise Erro("uso: tt --dono assinar ARQUIVO")
        print(assinar_arquivo(args[0]))
        return 0
    if cmd == "verificar":
        if not args:
            raise Erro("uso: tt --dono verificar ARQUIVO [ARQUIVO.sig]")
        ok, motivo = verificar_arquivo(args[0], args[1] if len(args) > 1 else None)
        print("assinatura confere" if ok else "NÃO confere: %s" % motivo)
        return 0 if ok else 1
    raise Erro("comando desconhecido: %s (tt --dono ajuda)" % cmd)


if __name__ == "__main__":
    try:
        sys.exit(principal(sys.argv[1:]))
    except Erro as e:
        print("✗ %s" % e, file=sys.stderr)
        sys.exit(2)
