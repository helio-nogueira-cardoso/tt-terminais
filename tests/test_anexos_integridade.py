"""Regressões de conteúdo e recuperação; arquivos fictícios, sem contas ou rede."""
import base64
import errno
import importlib.util
import io
from contextlib import redirect_stderr, redirect_stdout
from email import message_from_bytes, policy
from email.message import EmailMessage
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("email_tt", sys.argv.pop(1))
mail = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mail)


class Anexos(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.src, self.dst = self.root / "pendentes", self.root / "destino"
        self.src.mkdir()

    def salvar(self):
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            return mail.salvar_anexos(self.src, self.dst)

    def test_nomes_conteudo_colisao_e_link_quebrado(self):
        self.dst.mkdir()
        (self.dst / "ação (v2).pdf").write_bytes(b"anterior")
        (self.dst / "arquivo.txt").symlink_to(self.root / "ausente")
        nomes = ["ação (v2).pdf", "arquivo.txt", "..oculto", "linha\nseguinte.txt"]
        for nome in nomes:
            (self.src / nome).write_bytes(b"conteudo-\x00\xff")
        self.assertEqual(self.salvar(), 0)
        self.assertFalse(self.src.exists())
        self.assertEqual((self.dst / "ação (v2).pdf").read_bytes(), b"anterior")
        self.assertEqual((self.dst / "ação (v2) (2).pdf").read_bytes(), b"conteudo-\x00\xff")
        self.assertTrue((self.dst / "arquivo.txt").is_symlink())
        self.assertEqual((self.dst / "arquivo (2).txt").read_bytes(), b"conteudo-\x00\xff")
        self.assertFalse(list(self.dst.glob(".tt-anexo-*")))

    def test_disco_cheio_preserva_origem_e_remove_so_temporario(self):
        original = self.src / "documento.pdf"
        original.write_bytes(b"documento integral")
        def interromper(entrada, saida, **kwargs):
            saida.write(entrada.read(3))
            raise OSError(errno.ENOSPC, "disco cheio simulado")
        with patch("shutil.copyfileobj", side_effect=interromper):
            self.assertEqual(self.salvar(), 1)
        self.assertEqual(original.read_bytes(), b"documento integral")
        self.assertEqual(list(self.dst.iterdir()), [])
        self.assertEqual(self.salvar(), 0)
        self.assertEqual((self.dst / original.name).read_bytes(), b"documento integral")

    def test_falha_parcial_pode_ser_retomada_sem_duplicar_sucessos(self):
        (self.src / "bom.pdf").write_bytes(b"bom")
        (self.src / "falha.pdf").write_bytes(b"pendente")
        link = mail.os.link
        def publicar(origem, destino):
            if Path(destino).name == "falha.pdf":
                raise PermissionError("destino recusou arquivo")
            return link(origem, destino)
        with patch.object(mail.os, "link", side_effect=publicar):
            self.assertEqual(self.salvar(), 1)
        self.assertEqual([p.name for p in self.src.iterdir()], ["falha.pdf"])
        self.assertEqual((self.dst / "bom.pdf").read_bytes(), b"bom")
        self.assertEqual(self.salvar(), 0)
        self.assertEqual(sorted(p.name for p in self.dst.iterdir()), ["bom.pdf", "falha.pdf"])

    def test_destino_sem_hardlinks_e_falha_na_copia_de_retorno(self):
        original = self.src / "documento.pdf"
        original.write_bytes(b"documento integral")
        with patch.object(mail.os, "link", side_effect=OSError(errno.EOPNOTSUPP, "sem hardlinks")):
            import shutil
            copiar = shutil.copyfileobj
            def segunda_copia_falha(entrada, saida, **kwargs):
                if str(entrada.name).startswith(str(self.dst)):
                    saida.write(b"parcial")
                    raise OSError(errno.ENOSPC, "disco cheio")
                return copiar(entrada, saida, **kwargs)
            with patch("shutil.copyfileobj", side_effect=segunda_copia_falha):
                self.assertEqual(self.salvar(), 1)
            self.assertEqual(original.read_bytes(), b"documento integral")
            self.assertEqual(list(self.dst.iterdir()), [])
            self.assertEqual(self.salvar(), 0)
        self.assertEqual((self.dst / original.name).read_bytes(), b"documento integral")

    def test_origem_substituida_durante_copia_fica_preservada(self):
        original = self.src / "documento.pdf"
        original.write_bytes(b"antigo")
        link = mail.os.link
        def publicar(origem, destino):
            link(origem, destino)
            original.unlink()
            original.write_bytes(b"novo conteudo")
        with patch.object(mail.os, "link", side_effect=publicar):
            self.assertEqual(self.salvar(), 1)
        self.assertEqual(original.read_bytes(), b"novo conteudo")
        self.assertEqual((self.dst / original.name).read_bytes(), b"antigo")

    def test_symlink_e_pasta_na_origem_sao_recusados_sem_apagar(self):
        segredo = self.root / "fora.txt"
        segredo.write_bytes(b"fora do lote")
        (self.src / "link.txt").symlink_to(segredo)
        (self.src / "pasta").mkdir()
        self.assertEqual(self.salvar(), 1)
        self.assertEqual(segredo.read_bytes(), b"fora do lote")
        self.assertTrue((self.src / "link.txt").is_symlink())
        self.assertTrue((self.src / "pasta").is_dir())

    def test_eml_roundtrip_cli_e_json_microsoft(self):
        original = EmailMessage()
        original["From"] = "origem@example.invalid"
        original["Subject"] = "Mensagem anexada ç"
        original.set_content("corpo original")
        original.add_attachment(b"PDF-interior", maintype="application", subtype="pdf", filename="interno.pdf")
        f = self.root / "original.eml"
        f.write_bytes(original.as_bytes())
        args = mail.enviar_args(["--para", "destino@example.invalid", "--assunto", "Encaminhar",
                                 "--anexo", str(f), "--sem-assinatura"])
        msg = mail.montar_mensagem({"endereco": "origem@example.invalid"}, args, "Segue anexo")
        msg = message_from_bytes(msg.as_bytes(), policy=policy.default)
        payload = mail.outlook_json(msg)["Message"]["Attachments"][0]
        self.assertEqual(payload["Name"], "original.eml")
        inner = message_from_bytes(base64.b64decode(payload["ContentBytes"]), policy=policy.default)
        self.assertEqual(inner["Subject"], original["Subject"])
        self.assertIn("corpo original", inner.get_body(("plain",)).get_content())
        self.assertEqual(next(inner.iter_attachments()).get_payload(decode=True), b"PDF-interior")

    def test_html_inline_e_pdf_nao_viram_anexos_vazios(self):
        msg = EmailMessage()
        msg.set_content("texto alternativo")
        msg.add_alternative('<p>Imagem <img src="cid:foto"></p>', subtype="html")
        msg.get_payload()[1].add_related(b"PNG-ficticio", maintype="image", subtype="png", cid="<foto>")
        msg.add_attachment(b"PDF-ficticio", maintype="application", subtype="pdf", filename="ação.pdf", cid="<pdf>")
        msg = message_from_bytes(msg.as_bytes(), policy=policy.default)
        result = mail.outlook_json(msg)["Message"]
        self.assertEqual(result["Body"]["ContentType"], "HTML")
        self.assertEqual(len(result["Attachments"]), 2)
        foto, pdf = result["Attachments"]
        self.assertEqual((foto["ContentId"], foto["IsInline"]), ("foto", True))
        self.assertEqual(base64.b64decode(foto["ContentBytes"]), b"PNG-ficticio")
        self.assertEqual(base64.b64decode(pdf["ContentBytes"]), b"PDF-ficticio")
        self.assertFalse(pdf["IsInline"])  # ter CID não transforma um anexo explícito em inline

    def test_eml_conta_para_limite_e_formato_nao_suportado_falha(self):
        inner = EmailMessage(); inner.set_content("X" * 500)
        msg = EmailMessage(); msg.set_content("corpo"); msg.add_attachment(inner, filename="original.eml")
        with patch.object(mail, "OUTLOOK_LIMITE_ANEXOS", 100):
            with self.assertRaises(RuntimeError):
                mail.outlook_json(msg)
        multipart = EmailMessage(); multipart.make_mixed()
        multipart["Content-Disposition"] = 'attachment; filename="estrutura.mime"'
        with self.assertRaises(ValueError):
            mail.anexo_bytes(multipart)


if __name__ == "__main__":
    unittest.main()
