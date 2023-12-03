# convert dnGREP xml to mightygrep ini

$infile = $(Join-Path $(Get-Location) "dnGREP.Settings.dat")
$outfile = $(Join-Path $(Get-Location) "mightygrep.ini")
[xml]$global:xml = Get-Content -Path $infile
if (Test-Path $outfile) {
    Clear-Content -Path $outfile
}

function WriteLine {
    param ( $Line )
    echo $Line
    echo $Line | Out-File -FilePath $outfile -Append -Encoding utf8
}

function GetValue {
    param( $key )
    return $($global:xml.dictionary.item | Where-Object {$_.key -eq $key} | Select-Object -ExpandProperty '#text')
}

function WriteKey {
    param( $cfg, $key )
    WriteLine $($cfg + " = " + $(GetValue $key))
}

function WriteKeyArray {
    param( $cfg, $key )
    WriteLine $($cfg + " =")
    $value = $($global:xml.dictionary.item | Where-Object {$_.key -eq $key})
    foreach ($_ in $value.stringArray.string) {
        $line = $($_ | Select-Object -ExpandProperty '#text')
        if ($cfg -eq "filter_history") {
            $line = $line.Replace(";", " ")
        }
        WriteLine $line
    }
    WriteLine ">`tLIST_END"
}

$hlm = GetValue "HighlightMatches"
$dhlm = if ($hlm -eq "False") { 1 } else { 0 }
WriteLine $("disable_match_coloring = " + $dhlm)

$cp = GetValue "CodePage"
if ($cp -eq "-1") { $cp = 65001 }
WriteLine $("codepage = " + $cp)

$editor = $(GetValue "CustomEditor") + " " + $(GetValue "CustomEditorArgs")
$editor = $editor.Replace("%file", '$filepath')
$editor = $editor.Replace("%line", '$line')
$editor = $editor.Replace("%column", '$column')
WriteLine $("ctrl_click_match_command = " + $editor)

WriteKey "font_face" "ResultsFontFamily"
WriteKey "font_size" "ResultsFontSize"
WriteKeyArray "directory_history" "FastPathBookmarks"
WriteKeyArray "filter_history" "FastFileMatchBookmarks"
WriteKeyArray "pattern_history" "FastSearchBookmarks"
