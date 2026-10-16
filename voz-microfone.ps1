# voz-microfone.ps1 — o microfone do Windows para o 🎤 do tt no WSL (o WSL só ouve o microfone PADRÃO do Windows, pelo
# WSLg; este grava de um microfone escolhido, sem mudar o padrão, que é o das chamadas).
#   powershell.exe -File voz-microfone.ps1 listar          "índice<TAB>padrao,comunicacao<TAB>nome curto<TAB>nome" de cada um
#   powershell.exe -File voz-microfone.ps1 gravar N         PCM s16le mono 16 kHz do microfone N no stdout, até fecharem
# Usa o winmm (waveIn) e, para saber o padrão, o MMDevice; o C# é compilado uma vez numa DLL em %TEMP%.
param([string]$acao = 'listar', [int]$indice = -1)
$ErrorActionPreference = 'Stop'
$fonte = @'
using System; using System.IO; using System.Runtime.InteropServices; using System.Threading; using System.Text;
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

  [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class Enumerador {}
  [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IEnum { int EnumAudioEndpoints(int f, int m, out IntPtr d); int GetDefaultAudioEndpoint(int f, int r, out IDev e); }
  [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IDev { int Activate(ref Guid i, int c, IntPtr p, out IntPtr o); int OpenPropertyStore(int a, out IntPtr s); int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id); }

  // o id do MMDevice do microfone padrão (papel 0 = console, 2 = comunicação)
  static string Padrao(int papel) {
    try { IDev d; ((IEnum)new Enumerador()).GetDefaultAudioEndpoint(1, papel, out d); string id; d.GetId(out id); return id; }
    catch { return ""; }
  }
  // o id do MMDevice de um microfone do waveIn (DRV_QUERYFUNCTIONINSTANCEID): casa com o padrão sem depender do nome
  static string IdDe(int i) {
    int tam; if (MsgTam(new IntPtr(i), 0x0812, out tam, IntPtr.Zero) != 0 || tam <= 0) return "";
    var b = new StringBuilder(tam / 2 + 1); return MsgId(new IntPtr(i), 0x0811, b, new IntPtr(tam)) == 0 ? b.ToString() : "";
  }
  // o nome inteiro ("Microphone (BlackShark V2 Pro PS 2.4)"; o waveIn corta em 31 letras), pelo registro do MMDevice
  static string NomeDe(string id, string curto) {
    try {
      using (var k = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(
          @"SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Capture\" + id.Substring(id.LastIndexOf('.') + 1) + @"\Properties")) {
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
if (-not (Test-Path $dll)) { Add-Type -TypeDefinition $fonte -OutputAssembly $dll -OutputType Library }
Add-Type -Path $dll
if ($acao -eq 'gravar') { exit [TtMic]::Gravar($indice) }
[Console]::OutputEncoding = [Text.Encoding]::UTF8  # os nomes chegam ao WSL em UTF-8 ("Intel®")
[Console]::Out.Write([TtMic]::Listar())
