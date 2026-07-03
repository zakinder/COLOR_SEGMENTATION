param(
    [switch]$KeepExistingOutputs
)

$ErrorActionPreference = "Stop"

# Run from this testbench project root, even when launched from Scripts.
Set-Location (Join-Path $PSScriptRoot "..")

Write-Host "============================================================"
Write-Host "1000x500 Automated 28-Output RGB-HSV / Flat-Segment Testbench"
Write-Host "Project: $PWD"
Write-Host "============================================================"
Write-Host ""

if (-not (Get-Command ghdl -ErrorAction SilentlyContinue)) {
    throw "ghdl was not found in PATH. Install GHDL or add the GHDL bin folder to PATH."
}

if (-not (Test-Path "Input_Image/1000_500.bmp")) {
    throw "Input_Image/1000_500.bmp not found. Put your 1000x500 24-bit uncompressed BMP in Input_Image."
}

New-Item -ItemType Directory -Force -Path "Generated_Outputs" | Out-Null
New-Item -ItemType Directory -Force -Path "GHDL_Work" | Out-Null

if (-not $KeepExistingOutputs) {
    Write-Host "Cleaning old Generated_Outputs/*.bmp files so the folder ends with exactly the 28 requested outputs."
    Remove-Item "Generated_Outputs/*.bmp" -Force -ErrorAction SilentlyContinue
}

Remove-Item "GHDL_Work/work-obj*.cf" -Force -ErrorAction SilentlyContinue

Write-Host "Analyzing VHDL source files..."
& ghdl -a --std=08 --workdir=GHDL_Work "../Source_Files/flat_color_segment_pkg.vhd"; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& ghdl -a --std=08 --workdir=GHDL_Work "../Source_Files/div16_8_8.vhd"; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& ghdl -a --std=08 --workdir=GHDL_Work "../Source_Files/rgb_hsv.vhd"; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& ghdl -a --std=08 --workdir=GHDL_Work "../Source_Files/hsv2rgb.vhd"; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& ghdl -a --std=08 --workdir=GHDL_Work "Testbench_Files/tb_rgb_hsv2rgb_match_input_bmp.vhd"; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Elaborating testbench..."
& ghdl -e --std=08 --workdir=GHDL_Work tb_rgb_hsv2rgb_match_input_bmp; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$OutputFileNames = @(
    "FlatSeg_Slt_60_Vdark_40_Vwhite_240_Maj_5_Pass_0.bmp",
    "FlatSeg_Slt_60_Vdark_40_Vwhite_240_Maj_5_Pass_0 - Copy.bmp",
    "FlatSeg_Slt_30_Vdark_40_Vwhite_240_Maj_5_Pass_0.bmp",
    "FlatSeg_Slt_60_Vdark_40_Vwhite_240_Maj_5_Pass_3.bmp",
    "Ho_0_Sgp_125_So_0_Vgp_100_Vo_0_Enf_t_Hs_64_Ss_40_Vs_16_Fcb_t.bmp",
    "Ho_0_Sgp_100_So_0_Vgp_100_Vo_0_Enf_t_Hs_32_Ss_40_Vs_16_Fcb_t.bmp",
    "Ho_0_Sgp_100_So_0_Vgp_100_Vo_0_Enf_t_Hs_40_Ss_40_Vs_16_Fcb_t.bmp",
    "Ho_0_Sgp_100_So_0_Vgp_100_Vo_0_Enf_t_Hs_36_Ss_40_Vs_16_Fcb_t.bmp",
    "Ho_0_Sgp_100_So_0_Vgp_100_Vo_0_Enf_t_Hs_36_Ss_36_Vs_16_Fcb_t.bmp",
    "Ho_0_Sgp_100_So_0_Vgp_100_Vo_0_Enf_t_Hs_36_Ss_8_Vs_16_Fcb_t.bmp",
    "Ho_0_Sgp_100_So_0_Vgp_100_Vo_0_Enf_t_Hs_64_Ss_8_Vs_16_Fcb_t.bmp",
    "Ho_0_Sgp_100_So_0_Vgp_100_Vo_0_Enf_t_Hs_8_Ss_8_Vs_16_Fcb_t.bmp",
    "Ho_0_Sgp_100_So_0_Vgp_100_Vo_0_Enf_t_Hs_16_Ss_8_Vs_16_Fcb_t.bmp",
    "Ho_0_Sgp_100_So_0_Vgp_100_Vo_0_Enf_t_Hs_16_Ss_8_Vs_64_Fcb_t.bmp",
    "Ho_0_Sgp_100_So_0_Vgp_100_Vo_0_Enf_t_Hs_36_Ss_36_Vs_64_Fcb_t.bmp",
    "Ho_0_Sgp_100_So_0_Vgp_100_Vo_0_Enf_t_Hs_64_Ss_64_Vs_64_Fcb_t.bmp",
    "Ho_0_Sgp_100_So_0_Vgp_100_Vo_0_Enf_t_Hs_64_Ss_8_Vs_64_Fcb_t.bmp",
    "Ho_0_Sgp_100_So_0_Vgp_100_Vo_0_Enf_t_Hs_64_Ss_64_Vs_8_Fcb_t.bmp",
    "Ho_0_Sgp_100_So_0_Vgp_100_Vo_0_Enf_t_Hs_16_Ss_128_Vs_128_Fcb_t.bmp",
    "Ho_0_Sgp_100_So_0_Vgp_100_Vo_0_Enf_t_Hs_32_Ss_64_Vs_85_Fcb_t.bmp",
    "Ho_0_Sgp_100_So_0_Vgp_100_Vo_0_Enf_t_Hs_32_Ss_128_Vs_128_Fcb_t.bmp",
    "Ho_0_Sgp_100_So_0_Vgp_100_Vo_0_Enf_t_Hs_64_Ss_128_Vs_128_Fcb_t.bmp",
    "Ho_0_Sgp_100_So_0_Vgp_100_Vo_0_Enf_t_Hs_32_Ss_85_Vs_128_Fcb_t.bmp",
    "Ho_0_Sgp_100_So_0_Vgp_100_Vo_0_Enf_t_Hs_32_Ss_42_Vs_128_Fcb_t.bmp",
    "Ho_0_Sgp_100_So_0_Vgp_100_Vo_0_Enf_t_Hs_32_Ss_85_Vs_85_Fcb_t.bmp",
    "Ho_0_Sgp_100_So_0_Vgp_100_Vo_0_Enf_t_Hs_32_Ss_85_Vs_120_Fcb_t.bmp",
    "Ho_0_Sgp_100_So_0_Vgp_100_Vo_0_Enf_t_Hs_32_Ss_120_Vs_43_Fcb_t.bmp",
    "Ho_0_Sgp_100_So_0_Vgp_100_Vo_0_Enf_t_Hs_32_Ss_120_Vs_85_Fcb_t.bmp"
)

function Convert-TfToBoolString([string]$Token) {
    if ($Token -eq "t") { return "true" }
    if ($Token -eq "f") { return "false" }
    throw "Invalid boolean token: $Token"
}

function Get-GenericsFromOutputFilename([string]$FileName) {
    $args = New-Object System.Collections.Generic.List[string]
    $args.Add("-gINPUT_BMP_FILE=Input_Image/1000_500.bmp")
    $args.Add("-gOUTPUT_BMP_FILE=Generated_Outputs/$FileName")

    if ($FileName -match '^FlatSeg_Slt_(\d+)_Vdark_(\d+)_Vwhite_(\d+)_Maj_(\d+)_Pass_(\d+)(?: - Copy)?\.bmp$') {
        $args.Add("-gUSE_FLAT_SEGMENT_PACKAGE=true")
        $args.Add("-gFLAT_SEGMENT_SAT_THRESHOLD_LOW=$($Matches[1])")
        $args.Add("-gFLAT_SEGMENT_VALUE_DARK_LIMIT=$($Matches[2])")
        $args.Add("-gFLAT_SEGMENT_VALUE_WHITE_LIMIT=$($Matches[3])")
        $args.Add("-gFLAT_SEGMENT_MAJORITY_MIN_COUNT=$($Matches[4])")
        $args.Add("-gFLAT_SEGMENT_MAJORITY_PASSES=$($Matches[5])")
        return $args.ToArray()
    }

    if ($FileName -match '^Ho_(\d+)_Sgp_(\d+)_So_(\d+)_Vgp_(\d+)_Vo_(\d+)_Enf_([tf])_Hs_(\d+)_Ss_(\d+)_Vs_(\d+)_Fcb_([tf])\.bmp$') {
        $args.Add("-gUSE_FLAT_SEGMENT_PACKAGE=false")
        $args.Add("-gPREFILTER_MODE=3")
        $args.Add("-gRGB_HSV_HUE_OFFSET=$($Matches[1])")
        $args.Add("-gRGB_HSV_SATURATION_GAIN_PERCENT=$($Matches[2])")
        $args.Add("-gRGB_HSV_SATURATION_OFFSET=$($Matches[3])")
        $args.Add("-gRGB_HSV_VALUE_GAIN_PERCENT=$($Matches[4])")
        $args.Add("-gRGB_HSV_VALUE_OFFSET=$($Matches[5])")
        $args.Add("-gRGB_HSV_ENABLE_FLAT_COLOR=$(Convert-TfToBoolString $Matches[6])")
        $args.Add("-gRGB_HSV_HUE_STEP=$($Matches[7])")
        $args.Add("-gRGB_HSV_SATURATION_STEP=$($Matches[8])")
        $args.Add("-gRGB_HSV_VALUE_STEP=$($Matches[9])")
        $args.Add("-gRGB_HSV_FLAT_CENTER_BINS=$(Convert-TfToBoolString $Matches[10])")
        return $args.ToArray()
    }

    throw "Cannot decode testbench generics from generated-output filename: $FileName"
}

$LogPath = "Generated_Outputs/Run_All_28_Outputs_Log.txt"
"Automated 28-output run started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Set-Content $LogPath
"Input: Input_Image/1000_500.bmp" | Add-Content $LogPath
"" | Add-Content $LogPath

$caseIndex = 0
foreach ($fileName in $OutputFileNames) {
    $caseIndex++
    $outputPath = Join-Path "Generated_Outputs" $fileName
    $runArgs = Get-GenericsFromOutputFilename $fileName

    Write-Host ""
    Write-Host "[$caseIndex / $($OutputFileNames.Count)] Generating $fileName"
    "[$caseIndex / $($OutputFileNames.Count)] $fileName" | Add-Content $LogPath
    "  Generics: $($runArgs -join ' ')" | Add-Content $LogPath

    & ghdl -r --std=08 --workdir=GHDL_Work tb_rgb_hsv2rgb_match_input_bmp @runArgs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    if (-not (Test-Path $outputPath)) {
        throw "Simulation completed but expected output was not created: $outputPath"
    }
}

$generatedCount = (Get-ChildItem "Generated_Outputs" -Filter "*.bmp" | Measure-Object).Count
Write-Host ""
Write-Host "DONE. Generated BMP count: $generatedCount"
Get-ChildItem "Generated_Outputs" -Filter "*.bmp" | Sort-Object Name | Select-Object Name, Length | Format-Table -AutoSize
"" | Add-Content $LogPath
"Generated BMP count: $generatedCount" | Add-Content $LogPath
Get-ChildItem "Generated_Outputs" -Filter "*.bmp" | Sort-Object Name | ForEach-Object { "$($_.Name),$($_.Length)" } | Add-Content $LogPath

if ($generatedCount -ne 28) {
    throw "Expected exactly 28 BMP outputs, but found $generatedCount."
}

Write-Host "Log written to $LogPath"
