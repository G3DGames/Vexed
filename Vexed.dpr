program Vexed;

uses
  System.StartUpCopy,
  FMX.Forms,
  VexedMain in 'src\VexedMain.pas' {Form1},
{$if defined(MSWINDOWS)}
  DisplayData in 'common\DisplayData.pas',
  GpuPreference in 'common\GpuPreference.pas',
  {$if defined(WIN32)}
  Windows,
  {$ifend }
{$ifend }
  TileMapRenderer in 'src\TileMapRenderer.pas',
  PalmPDB in 'src\PalmPDB.pas'
  ;

// Win32 ONLY needs IMAGE_FILE_LARGE_ADDRESS_AWARE
{$if defined(MSWINDOWS) and defined(WIN32)}
{$SetPEFlags IMAGE_FILE_LARGE_ADDRESS_AWARE}
{$ifend}

{$R *.res}

// Choose which profile to default to
{$define HIPERF}
// {$define POWERSAVE}

begin
  { Report any dumb memory leaks - switch to false for release }
  ReportMemoryLeaksOnShutdown := True;
{$if defined(MSWINDOWS)}
  {$if defined(HIPERF)}
  SetGpuPreference(gpHighPerformance);
  {$elseif defined(POWERSAVE)}
  SetGpuPreference(gpPowerSaving);
  {$ELSE}
  SetGpuPreference(gpAutomatic);
  {$ifend}
{$ifend}


  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.

