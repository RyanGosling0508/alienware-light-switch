using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;
[assembly: AssemblyTitle("Alienware Light Switch")]
[assembly: AssemblyDescription("A small companion for AWCC lighting")]
[assembly: AssemblyVersion("1.0.3.0")]
[assembly: AssemblyFileVersion("1.0.3.0")]
[assembly: AssemblyCopyright("Copyright (c) 2026 RyanGosling0508")]
namespace LightSwitch {
 static class Palette {
  public static Color Background=Color.FromArgb(14,18,27), Panel=Color.FromArgb(23,30,42), Border=Color.FromArgb(46,58,76), Text=Color.FromArgb(238,244,252), Muted=Color.FromArgb(144,160,181), Accent=Color.FromArgb(91,224,196);
  public static GraphicsPath Round(RectangleF r,float radius){var p=new GraphicsPath();float d=radius*2;p.AddArc(r.X,r.Y,d,d,180,90);p.AddArc(r.Right-d,r.Y,d,d,270,90);p.AddArc(r.Right-d,r.Bottom-d,d,d,0,90);p.AddArc(r.X,r.Bottom-d,d,d,90,90);p.CloseFigure();return p;}
 }
 sealed class ModeButton : Button {
  public bool IsOn,Selected; bool hover;
  public ModeButton(bool on){IsOn=on;Text=on?"Lights on":"Lights off";AccessibleName=Text;AccessibleDescription=on?"Restore the current AWCC lighting effects":"Select AWCC Go Dark";FlatStyle=FlatStyle.Flat;FlatAppearance.BorderSize=0;Cursor=Cursors.Hand;SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer,true);}
  protected override void OnMouseEnter(EventArgs e){hover=true;Invalidate();base.OnMouseEnter(e);}
  protected override void OnMouseLeave(EventArgs e){hover=false;Invalidate();base.OnMouseLeave(e);}
  protected override void OnPaint(PaintEventArgs e){
   var g=e.Graphics;g.SmoothingMode=SmoothingMode.AntiAlias;float s=Width/276f;g.ScaleTransform(s,s);
   var rect=new RectangleF(1,1,274,142);
   using(var p=Palette.Round(rect,17))using(var b=new SolidBrush(Selected?Color.FromArgb(26,52,51):hover?Color.FromArgb(31,41,57):Palette.Panel))using(var pen=new Pen(Selected?Palette.Accent:Palette.Border,Selected?1.7f:1)){g.FillPath(b,p);g.DrawPath(pen,p);}
   Color ink=Enabled?(IsOn?Palette.Accent:Color.FromArgb(160,178,231)):Palette.Muted;
   using(var pen=new Pen(ink,2)){
    if(IsOn){g.DrawEllipse(pen,24,23,20,20);for(int i=0;i<8;i++){double a=i*Math.PI/4;g.DrawLine(pen,34+(float)Math.Cos(a)*15,33+(float)Math.Sin(a)*15,34+(float)Math.Cos(a)*19,33+(float)Math.Sin(a)*19);}}
    else {g.DrawArc(pen,23,20,25,25,40,280);g.DrawArc(pen,32,15,25,25,90,130);}
   }
   using(var f=new Font("Segoe UI Semibold",22,FontStyle.Regular,GraphicsUnit.Pixel))using(var b=new SolidBrush(Enabled?Palette.Text:Palette.Muted))g.DrawString(Text,f,b,22,66);
   using(var f=new Font("Segoe UI",12,FontStyle.Regular,GraphicsUnit.Pixel))using(var b=new SolidBrush(Palette.Muted))g.DrawString(IsOn?"Restore your current effects":"A quieter look, in one click",f,b,23,108);
   if(Selected){using(var b=new SolidBrush(Palette.Accent))g.FillEllipse(b,245,22,7,7);}
   if(Focused)using(var p=Palette.Round(new RectangleF(6,6,264,132),13))using(var pen=new Pen(Palette.Accent,1)){pen.DashStyle=DashStyle.Dot;g.DrawPath(pen,p);}
  }
 }
 sealed class ControlResult {public bool Success;public string Mode,Details;}
 static class Backend {
  public static readonly string LogRoot=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"AlienwareLightSwitch");
  public static string Script(){using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("AwccLighting.ps1"))using(var reader=new StreamReader(stream,Encoding.UTF8))return reader.ReadToEnd();}
  public static ControlResult Run(string mode){
   var result=new ControlResult{Mode=mode,Success=false};var output=new StringBuilder();
   try{
    Directory.CreateDirectory(LogRoot);
    string prefix="$Mode='"+mode+"';$Quiet=$true;$LogRoot='"+LogRoot.Replace("'","''")+"';\r\n";
    string encoded=Convert.ToBase64String(Encoding.Unicode.GetBytes(prefix+Script()));
    var info=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),@"System32\WindowsPowerShell\v1.0\powershell.exe"));
    info.Arguments="-NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -EncodedCommand "+encoded;
    info.WorkingDirectory=LogRoot;info.UseShellExecute=false;info.CreateNoWindow=true;info.RedirectStandardOutput=true;info.RedirectStandardError=true;
    using(var process=new Process()){
     process.StartInfo=info;process.OutputDataReceived+=(s,e)=>{if(e.Data!=null)lock(output)output.AppendLine(e.Data);};process.ErrorDataReceived+=(s,e)=>{if(e.Data!=null)lock(output)output.AppendLine(e.Data);};
     process.Start();process.BeginOutputReadLine();process.BeginErrorReadLine();
     if(!process.WaitForExit(90000)){process.Kill();throw new Exception("AWCC did not respond within 90 seconds. Open AWCC, finish any prompts, and try again.");}
     process.WaitForExit();result.Details=output.ToString();result.Success=process.ExitCode==0 && result.Details.Contains("AWCC_SELECTION_VERIFIED") && result.Details.Contains("after="+mode);
     if(!result.Success && result.Details.Length==0)result.Details="The AWCC lighting selection could not be verified.";
    }
   }catch(Exception error){result.Details=error.Message+Environment.NewLine+output.ToString();}
   try{File.WriteAllText(Path.Combine(LogRoot,"app-last.txt"),DateTime.Now.ToString("O")+Environment.NewLine+result.Details,Encoding.UTF8);}catch{}
   return result;
  }
 }
 sealed class MainWindow : Form {
  ModeButton on=new ModeButton(true),off=new ModeButton(false);Button details=new Button();
  string status="Choose a lighting mode.",subtitle="Your effects. Your choice.",lastDetails="No operation has run in this session.";bool busy=false,failed=false;string current="";
  public MainWindow(){
   Text="Alienware Light Switch";ClientSize=new Size(640,480);BackColor=Palette.Background;ForeColor=Palette.Text;Font=new Font("Segoe UI",10);FormBorderStyle=FormBorderStyle.FixedSingle;MaximizeBox=false;StartPosition=FormStartPosition.CenterScreen;
   AutoScaleMode=AutoScaleMode.None;DoubleBuffered=true;using(var display=Graphics.FromHwnd(IntPtr.Zero)){float dpi=display.DpiX/96f;ClientSize=new Size((int)(640*dpi),(int)(480*dpi));}
   using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("app.ico")){if(stream!=null)Icon=new Icon(stream);}
   on.Bounds=new Rectangle(32,218,276,144);off.Bounds=new Rectangle(332,218,276,144);on.Click+=(s,e)=>Apply("On");off.Click+=(s,e)=>Apply("Off");Controls.Add(on);Controls.Add(off);
   details.Text="View details";details.FlatStyle=FlatStyle.Flat;details.FlatAppearance.BorderSize=0;details.ForeColor=Palette.Muted;details.Cursor=Cursors.Hand;details.Bounds=new Rectangle(484,389,124,30);details.Click+=(s,e)=>ShowDetails();Controls.Add(details);
   LayoutControls();FormClosing+=(s,e)=>{if(busy){e.Cancel=true;status="Finishing the lighting change...";Invalidate();}};
  }
  [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h,int attr,ref int value,int size);
  protected override void OnHandleCreated(EventArgs e){base.OnHandleCreated(e);int dark=1;DwmSetWindowAttribute(Handle,20,ref dark,4);}
  void LayoutControls(){float s=ClientSize.Width/640f;on.Bounds=new Rectangle((int)(32*s),(int)(218*s),(int)(276*s),(int)(144*s));off.Bounds=new Rectangle((int)(332*s),(int)(218*s),(int)(276*s),(int)(144*s));details.Bounds=new Rectangle((int)(484*s),(int)(389*s),(int)(124*s),(int)(30*s));details.Font=new Font("Segoe UI",12*s,FontStyle.Regular,GraphicsUnit.Pixel);}
  protected override void OnPaint(PaintEventArgs e){
   base.OnPaint(e);var g=e.Graphics;g.SmoothingMode=SmoothingMode.AntiAlias;float s=ClientSize.Width/640f;g.ScaleTransform(s,s);
   using(var pen=new Pen(Palette.Accent,2)){g.DrawArc(pen,34,31,22,22,-55,290);g.DrawLine(pen,45,27,45,40);}
   Draw(g,"LIGHT SWITCH",new Font("Segoe UI Semibold",13,FontStyle.Regular,GraphicsUnit.Pixel),Palette.Text,68,31);
   using(var p=Palette.Round(new RectangleF(464,27,144,30),15))using(var b=new SolidBrush(Palette.Panel)){g.FillPath(b,p);}Draw(g,"AWCC COMPANION",new Font("Segoe UI",11,FontStyle.Regular,GraphicsUnit.Pixel),Palette.Muted,480,34);
   Draw(g,"Set the mood.",new Font("Segoe UI Semibold",40,FontStyle.Regular,GraphicsUnit.Pixel),Palette.Text,28,87);
   Draw(g,subtitle,new Font("Segoe UI",15,FontStyle.Regular,GraphicsUnit.Pixel),Palette.Muted,32,147);
   using(var pen=new Pen(Color.FromArgb(35,47,61),1)){g.DrawLine(pen,32,190,608,190);g.DrawLine(pen,32,437,608,437);}
   Color dot=busy?Color.FromArgb(239,188,103):failed?Color.FromArgb(248,126,132):current.Length>0?Palette.Accent:Palette.Muted;
   using(var b=new SolidBrush(dot))g.FillEllipse(b,34,400,7,7);
   Draw(g,status,new Font("Segoe UI",12,FontStyle.Regular,GraphicsUnit.Pixel),Palette.Text,51,393);
   Draw(g,"LOCAL CONTROL  /  NO BACKGROUND SERVICE",new Font("Segoe UI",11,FontStyle.Regular,GraphicsUnit.Pixel),Palette.Muted,32,454);
   Draw(g,"v1.0.3",new Font("Segoe UI",11,FontStyle.Regular,GraphicsUnit.Pixel),Palette.Muted,578,454);
  }
  static void Draw(Graphics g,string text,Font f,Color color,float x,float y){using(f)using(var b=new SolidBrush(color))g.DrawString(text,f,b,x,y);}
  void Apply(string mode){
   if(busy)return;busy=true;failed=false;on.Enabled=off.Enabled=false;status="Connecting to Alienware Command Center...";subtitle="Your existing AWCC window stays yours.";Invalidate();
   ThreadPool.QueueUserWorkItem(_=>{var result=Backend.Run(mode);if(IsDisposed)return;BeginInvoke((Action)(()=>{
    busy=false;failed=!result.Success;on.Enabled=off.Enabled=true;lastDetails=result.Details;
    if(result.Success){current=mode;on.Selected=mode=="On";off.Selected=mode=="Off";status=mode=="On"?"Lights on. AWCC selection verified.":"Lights off. AWCC selection verified.";subtitle=mode=="On"?"Your current effects are back.":"A little less glow. Everything else stays yours.";}
    else{status="Could not change lighting. View details.";subtitle="Open AWCC and check that Go Light / Go Dark is available.";}
    on.Invalidate();off.Invalidate();Invalidate();
   }));});
  }
  void ShowDetails(){using(var dialog=new Form())using(var box=new TextBox()){
   dialog.Text="Operation details";dialog.ClientSize=new Size(680,400);dialog.StartPosition=FormStartPosition.CenterParent;box.Multiline=true;box.ReadOnly=true;box.ScrollBars=ScrollBars.Both;box.WordWrap=false;box.Dock=DockStyle.Fill;box.Font=new Font("Consolas",9);box.Text=lastDetails+"\r\n\r\nLogs: "+Backend.LogRoot;dialog.Controls.Add(box);dialog.ShowDialog(this);
  }}
  public void Render(string path){Show();Application.DoEvents();using(var bitmap=new Bitmap(Width,Height)){DrawToBitmap(bitmap,new Rectangle(0,0,Width,Height));bitmap.Save(path,System.Drawing.Imaging.ImageFormat.Png);}Close();}
 }
 static class Program {
  [STAThread] static int Main(string[] args){
   if(args.Length==2 && args[0]=="--verify" && (args[1]=="On"||args[1]=="Off"))return Backend.Run(args[1]).Success?0:1;
   Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
   using(var window=new MainWindow()){
    if(args.Length==2 && args[0]=="--render-preview"){window.Render(args[1]);return 0;}
    Application.Run(window);
   }
   return 0;
  }
 }
}
