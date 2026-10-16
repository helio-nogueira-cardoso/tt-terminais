# voz-windows.ps1 — o microfone e o alto-falante do Windows para o 🎤 do tt no WSL. O WSL só ouve o microfone PADRÃO e
# só toca no alto-falante PADRÃO (pelo WSLg), e a voz do Windows também fala no padrão; este grava de um microfone e
# fala num aparelho escolhidos (o headset), sem mudar os padrões, que são os das chamadas.
#   powershell.exe -File voz-windows.ps1 listar     "índice<TAB>padrao,comunicacao<TAB>nome curto<TAB>nome" dos microfones
#   powershell.exe -File voz-windows.ps1 saidas     o mesmo das saídas de som
#   powershell.exe -File voz-windows.ps1 gravar N   PCM s16le mono 16 kHz do microfone N no stdout, até fecharem
#   powershell.exe -File voz-windows.ps1 falar      imprime as saídas e "--"; depois lê do stdin "D n" (saída n; -1 = a
#                                                   padrão), "F base64" (fala o texto UTF-8 com a voz pt-BR do Windows),
#                                                   "T base64" (toca um WAV de 16 bits: a voz neural gerada no motor) e
#                                                   "P" (para o que está tocando ou na fila); responde "fim" a cada F ou T
# Usa o winmm (waveIn/waveOut), o MMDevice (os padrões) e o System.Speech; o C# é compilado uma vez numa DLL em %TEMP%.
param([string]$acao = 'listar', [int]$indice = -1)
$ErrorActionPreference = 'Stop'
$fonte = @'
using System; using System.IO; using System.Runtime.InteropServices; using System.Threading; using System.Text;
using System.Collections.Concurrent; using System.Speech.Synthesis; using System.Speech.AudioFormat;
public static class TtMic {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  struct CAPS { public short mid; public short pid; public int ver;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string nome; public int formatos; public short canais; public short res; }
  [StructLayout(LayoutKind.Sequential)]
  struct FMT { public short tag; public short canais; public int taxa; public int bps; public short bloco; public short bits; public short extra; }
  [StructLayout(LayoutKind.Sequential)]
  struct HDR { public IntPtr dados; public int tam; public int gravados; public IntPtr usuario; public int flags; public int loops; public IntPtr prox; public IntPtr res; }
  [DllImport("winmm.dll")] static extern int waveInGetNumDevs();
  [DllImport("winmm.dll", CharSet = CharSet.Unicode, EntryPoint = "waveInGetDevCapsW")] static extern int Caps(IntPtr id, ref CAPS c, int t);
  [DllImport("winmm.dll")] static extern int waveInOpen(out IntPtr h, IntPtr id, ref FMT f, IntPtr cb, IntPtr inst, int fl);
  [DllImport("winmm.dll")] static extern int waveInPrepareHeader(IntPtr h, IntPtr hdr, int t);
  [DllImport("winmm.dll")] static extern int waveInUnprepareHeader(IntPtr h, IntPtr hdr, int t);
  [DllImport("winmm.dll")] static extern int waveInAddBuffer(IntPtr h, IntPtr hdr, int t);
  [DllImport("winmm.dll")] static extern int waveInStart(IntPtr h);
  [DllImport("winmm.dll")] static extern int waveInReset(IntPtr h);
  [DllImport("winmm.dll")] static extern int waveInClose(IntPtr h);
  [DllImport("winmm.dll", EntryPoint = "waveInMessage")] static extern int MsgTam(IntPtr id, int msg, out int tam, IntPtr nada);
  [DllImport("winmm.dll", EntryPoint = "waveInMessage", CharSet = CharSet.Unicode)]
  static extern int MsgId(IntPtr id, int msg, StringBuilder buf, IntPtr tam);
  [DllImport("winmm.dll")] static extern int waveOutGetNumDevs();
  [DllImport("winmm.dll", CharSet = CharSet.Unicode, EntryPoint = "waveOutGetDevCapsW")] static extern int CapsSai(IntPtr id, ref CAPSSAI c, int t);
  [DllImport("winmm.dll", EntryPoint = "waveOutMessage")] static extern int MsgTamSai(IntPtr id, int msg, out int tam, IntPtr nada);
  [DllImport("winmm.dll", EntryPoint = "waveOutMessage", CharSet = CharSet.Unicode)]
  static extern int MsgIdSai(IntPtr id, int msg, StringBuilder buf, IntPtr tam);
  [DllImport("winmm.dll")] static extern int waveOutOpen(out IntPtr h, IntPtr id, ref FMT f, IntPtr cb, IntPtr inst, int fl);
  [DllImport("winmm.dll")] static extern int waveOutPrepareHeader(IntPtr h, IntPtr hdr, int t);
  [DllImport("winmm.dll")] static extern int waveOutUnprepareHeader(IntPtr h, IntPtr hdr, int t);
  [DllImport("winmm.dll")] static extern int waveOutWrite(IntPtr h, IntPtr hdr, int t);
  [DllImport("winmm.dll")] static extern int waveOutReset(IntPtr h);
  [DllImport("winmm.dll")] static extern int waveOutClose(IntPtr h);
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  struct CAPSSAI { public short mid; public short pid; public int ver;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string nome; public int formatos; public short canais; public short res; public int sup; }

  [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class Enumerador {}
  [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IEnum { int EnumAudioEndpoints(int f, int m, out IntPtr d); int GetDefaultAudioEndpoint(int f, int r, out IDev e); }
  [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IDev { int Activate(ref Guid i, int c, IntPtr p, out IntPtr o); int OpenPropertyStore(int a, out IntPtr s); int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id); }

  // o id do MMDevice do microfone padrão (papel 0 = console, 2 = comunicação)
  static string Padrao(int papel, int fluxo = 1) {
    try { IDev d; ((IEnum)new Enumerador()).GetDefaultAudioEndpoint(fluxo, papel, out d); string id; d.GetId(out id); return id; }
    catch { return ""; }
  }
  // o id do MMDevice de um microfone do waveIn (DRV_QUERYFUNCTIONINSTANCEID): casa com o padrão sem depender do nome
  static string IdDe(int i) {
    int tam; if (MsgTam(new IntPtr(i), 0x0812, out tam, IntPtr.Zero) != 0 || tam <= 0) return "";
    var b = new StringBuilder(tam / 2 + 1); return MsgId(new IntPtr(i), 0x0811, b, new IntPtr(tam)) == 0 ? b.ToString() : "";
  }
  // o nome inteiro ("Microphone (BlackShark V2 Pro PS 2.4)"; o waveIn corta em 31 letras), pelo registro do MMDevice
  static string IdSai(int i) {
    int tam; if (MsgTamSai(new IntPtr(i), 0x0812, out tam, IntPtr.Zero) != 0 || tam <= 0) return "";
    var b = new StringBuilder(tam / 2 + 1); return MsgIdSai(new IntPtr(i), 0x0811, b, new IntPtr(tam)) == 0 ? b.ToString() : "";
  }
  static string NomeDe(string id, string curto, string tipo = "Capture") {
    try {
      using (var k = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(
          @"SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\" + tipo + @"\" + id.Substring(id.LastIndexOf('.') + 1) + @"\Properties")) {
        string n = k == null ? null : k.GetValue("{a45c254e-df1c-4efd-8020-67d146a850e0},2") as string;
        string d = k == null ? null : k.GetValue("{b3f8fa53-0004-438e-9003-51a46e139bfc},6") as string;
        return n == null ? curto : n + (d == null ? "" : " (" + d + ")");
      }
    } catch { return curto; }
  }

  public static string Listar() {
    var sb = new StringBuilder();
    string p0 = Padrao(0), p2 = Padrao(2);
    for (int i = 0; i < waveInGetNumDevs(); i++) {
      var c = new CAPS(); if (Caps(new IntPtr(i), ref c, Marshal.SizeOf(typeof(CAPS))) != 0) continue;
      string id = IdDe(i), marca = "";
      if (id.Length > 0 && id == p0) marca += "padrao,";
      if (id.Length > 0 && id == p2) marca += "comunicacao,";
      sb.Append(i).Append('\t').Append(marca.TrimEnd(',')).Append('\t').Append(c.nome).Append('\t')
        .Append(id.Length > 0 ? NomeDe(id, c.nome) : c.nome).Append('\n');
    }
    return sb.ToString();
  }

  public static string Saidas() {
    var sb = new StringBuilder();
    string p0 = Padrao(0, 0), p2 = Padrao(2, 0);
    for (int i = 0; i < waveOutGetNumDevs(); i++) {
      var c = new CAPSSAI(); if (CapsSai(new IntPtr(i), ref c, Marshal.SizeOf(typeof(CAPSSAI))) != 0) continue;
      string id = IdSai(i), marca = "";
      if (id.Length > 0 && id == p0) marca += "padrao,";
      if (id.Length > 0 && id == p2) marca += "comunicacao,";
      sb.Append(i).Append('\t').Append(marca.TrimEnd(',')).Append('\t').Append(c.nome).Append('\t')
        .Append(id.Length > 0 ? NomeDe(id, c.nome, "Render") : c.nome).Append('\n');
    }
    return sb.ToString();
  }

  // toca PCM 16 bits mono na saída dev (-1 = a padrão); cancelado() para no meio
  // o PCM de 16 bits de um WAV (os pedaços "fmt " e "data")
  static bool LerWav(byte[] w, out byte[] pcm, out int taxa, out short canais) {
    pcm = null; taxa = 0; canais = 1; short bits = 0;
    if (w.Length < 44 || Encoding.ASCII.GetString(w, 0, 4) != "RIFF") return false;
    for (int p = 12; p + 8 <= w.Length; ) {
      string id = Encoding.ASCII.GetString(w, p, 4); int tam = BitConverter.ToInt32(w, p + 4);
      if (id == "fmt ") { canais = BitConverter.ToInt16(w, p + 10); taxa = BitConverter.ToInt32(w, p + 12); bits = BitConverter.ToInt16(w, p + 22); }
      else if (id == "data") {
        if (tam < 0 || p + 8 + tam > w.Length) tam = w.Length - p - 8;
        pcm = new byte[tam]; Array.Copy(w, p + 8, pcm, 0, tam);
      }
      if (tam < 0) break;
      p += 8 + tam + (tam & 1);
    }
    return pcm != null && taxa > 0 && bits == 16;
  }

  static void Tocar(int dev, byte[] pcm, int taxa, Func<bool> cancelado, short canais = 1) {
    var f = new FMT { tag = 1, canais = canais, taxa = taxa, bps = taxa * 2 * canais, bloco = (short)(2 * canais), bits = 16, extra = 0 };
    IntPtr h; int r = waveOutOpen(out h, new IntPtr(dev), ref f, IntPtr.Zero, IntPtr.Zero, 0);
    if (r != 0) throw new Exception("waveOutOpen " + r);
    int th = Marshal.SizeOf(typeof(HDR)), off = (int)Marshal.OffsetOf(typeof(HDR), "flags");
    IntPtr dados = Marshal.AllocHGlobal(pcm.Length), ph = Marshal.AllocHGlobal(th);
    try {
      Marshal.Copy(pcm, 0, dados, pcm.Length);
      Marshal.StructureToPtr(new HDR { dados = dados, tam = pcm.Length }, ph, false);
      waveOutPrepareHeader(h, ph, th); waveOutWrite(h, ph, th);
      while ((Marshal.ReadInt32(ph, off) & 1) == 0) { if (cancelado()) { waveOutReset(h); break; } Thread.Sleep(20); }
      waveOutUnprepareHeader(h, ph, th);
    } finally { waveOutClose(h); Marshal.FreeHGlobal(dados); Marshal.FreeHGlobal(ph); }
  }

  public static int Falar() {
    Console.Out.Write(Saidas()); Console.Out.WriteLine("--"); Console.Out.Flush();
    var voz = new SpeechSynthesizer();
    foreach (var v in voz.GetInstalledVoices())
      if (v.Enabled && v.VoiceInfo.Culture.Name == "pt-BR") { voz.SelectVoice(v.VoiceInfo.Name); break; }
    voz.Rate = 1;
    var fila = new BlockingCollection<Tuple<int, string>>();
    int lidos = 0, canceladosAte = 0, dev = -1;
    var leitor = new Thread(() => {
      string l;
      while ((l = Console.In.ReadLine()) != null) {
        if (l == "P") { Interlocked.Exchange(ref canceladosAte, lidos); continue; }
        if (l.StartsWith("F ") || l.StartsWith("T ")) { lidos++; fila.Add(Tuple.Create(lidos, l)); }
        else if (l.StartsWith("D ")) fila.Add(Tuple.Create(0, l));
      }
      fila.CompleteAdding();
    });
    leitor.IsBackground = true; leitor.Start();
    foreach (var item in fila.GetConsumingEnumerable()) {
      if (item.Item1 == 0) { int.TryParse(item.Item2.Substring(2), out dev); continue; }
      int n = item.Item1;
      try {
        if (n > canceladosAte && item.Item2.StartsWith("T ")) {
          byte[] pcm; int taxa; short canais;
          if (!LerWav(Convert.FromBase64String(item.Item2.Substring(2).Trim()), out pcm, out taxa, out canais)) throw new Exception("WAV inválido");
          Tocar(dev, pcm, taxa, () => n <= canceladosAte, canais);
        } else if (n > canceladosAte) {
          string texto = Encoding.UTF8.GetString(Convert.FromBase64String(item.Item2.Substring(2).Trim()));
          var ms = new MemoryStream();
          voz.SetOutputToAudioStream(ms, new SpeechAudioFormatInfo(22050, AudioBitsPerSample.Sixteen, AudioChannel.Mono));
          voz.Speak(texto); voz.SetOutputToNull();
          if (n > canceladosAte) Tocar(dev, ms.ToArray(), 22050, () => n <= canceladosAte);
        }
        Console.Out.WriteLine("fim");
      } catch (Exception e) { Console.Out.WriteLine("erro " + e.Message.Replace('\n', ' ')); }
      Console.Out.Flush();
    }
    return 0;
  }

  public static int Gravar(int dev) {
    var f = new FMT { tag = 1, canais = 1, taxa = 16000, bps = 32000, bloco = 2, bits = 16, extra = 0 };
    IntPtr h; int r = waveInOpen(out h, new IntPtr(dev), ref f, IntPtr.Zero, IntPtr.Zero, 0);
    if (r != 0) { Console.Error.WriteLine("waveInOpen: " + r); return r; }
    int n = 8, tam = 1600, th = Marshal.SizeOf(typeof(HDR)), off = (int)Marshal.OffsetOf(typeof(HDR), "flags");
    int offg = (int)Marshal.OffsetOf(typeof(HDR), "gravados");
    var hs = new IntPtr[n]; var buf = new byte[tam];
    for (int i = 0; i < n; i++) {
      var hd = new HDR { dados = Marshal.AllocHGlobal(tam), tam = tam };
      hs[i] = Marshal.AllocHGlobal(th); Marshal.StructureToPtr(hd, hs[i], false);
      waveInPrepareHeader(h, hs[i], th); waveInAddBuffer(h, hs[i], th);
    }
    waveInStart(h);
    var saida = Console.OpenStandardOutput();
    try {
      for (int i = 0; ; i = (i + 1) % n) {
        while ((Marshal.ReadInt32(hs[i], off) & 1) == 0) Thread.Sleep(5);  // WHDR_DONE
        int g = Marshal.ReadInt32(hs[i], offg);
        Marshal.Copy(Marshal.ReadIntPtr(hs[i]), buf, 0, g);
        saida.Write(buf, 0, g); saida.Flush();
        waveInAddBuffer(h, hs[i], th);
      }
    } catch (IOException) { } finally { waveInReset(h); for (int i = 0; i < n; i++) waveInUnprepareHeader(h, hs[i], th); waveInClose(h); }
    return 0;
  }
}
'@
$dll = Join-Path $env:TEMP ('tt-voz-mic-' + [BitConverter]::ToString((New-Object Security.Cryptography.SHA1Managed).ComputeHash(
  [Text.Encoding]::UTF8.GetBytes($fonte))).Replace('-', '').Substring(0, 12) + '.dll')
Add-Type -AssemblyName System.Speech
if (-not (Test-Path $dll)) { Add-Type -TypeDefinition $fonte -ReferencedAssemblies System.Speech -OutputAssembly $dll -OutputType Library }
Add-Type -Path $dll
[Console]::OutputEncoding = [Text.Encoding]::UTF8  # os nomes chegam ao WSL em UTF-8 ("Intel®")
[Console]::InputEncoding = [Text.Encoding]::UTF8
if ($acao -eq 'gravar') { exit [TtMic]::Gravar($indice) }
if ($acao -eq 'falar') { exit [TtMic]::Falar() }
if ($acao -eq 'saidas') { [Console]::Out.Write([TtMic]::Saidas()); exit 0 }
[Console]::Out.Write([TtMic]::Listar())
