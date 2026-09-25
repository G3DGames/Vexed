program Vexed;

uses
  System.StartUpCopy,
  FMX.Forms,
  VexedMain in 'src\VexedMain.pas' {Form1},
  DisplayData in 'common\DisplayData.pas',
  GpuPreference in 'common\GpuPreference.pas',
  TileMapRenderer in 'src\TileMapRenderer.pas';

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

