# convert grepWin configuration settings to mightygrep
# reads from registry or grepwin.ini in the script's directory

$infile = $(Join-Path $(Get-Location) "grepwin.ini")
$outfile = $(Join-Path $(Get-Location) "mightygrep.ini")
if (Test-Path $outfile) {
    Clear-Content -Path $outfile
}

function WriteLine {
    param ( $Line )
    echo $Line
    echo $Line | Out-File -FilePath $outfile -Append -Encoding utf8
}

$editorcmd = ""
$paths = @()
$filters = @()
$patterns = @()
$utf8 = $false

if (Test-Path $infile)
{
    # read grepWin config from INI
    $global:file = Get-Content $infile
    function GetIniValue 
    {
        param( $name )
        $result = ""
        $regex = "^" + $name + "\W"
        $matches = $global:file -match $regex
        if ($matches.Length -gt 0)
        {
            $line = $matches[0]
            $result = $line.Substring($line.IndexOf('=') + 1)
        }
        return $result
    }

    $editorcmd = GetIniValue "editorcmd"
    
    # directories
    $paths += GetIniValue "searchpath"
    for ($i = 0; <# read until missing key #>; $i++) 
    {
        $iter = $(GetIniValue $("SearchPaths" + $i.ToString()))
        if ($iter.Length -gt 0)
        {
            $paths += $iter
        }
        else
        {
            break;
        }
    }

    # filters
    for ($i = 0; <# read until missing key #>; $i++) 
    {
        $iter = $(GetIniValue $("FilePattern" + $i.ToString()))
        if ($iter.Length -gt 0)
        {
            $filters += $iter.replace("|", " ")
        }
        else
        {
            break;
        }
    }

    # patterns
    $pattern = $(GetIniValue "pattern")
    if ($pattern.Length -ne 0) { $patterns += $pattern }
    for ($i = 0; <# read until missing key #>; $i++) 
    {
        $iter = $(GetIniValue $("SearchPattern" + $i.ToString()))
        if ($iter.Length -gt 0)
        {
            $patterns += $iter
        }
        else
        {
            break;
        }
    }
}
else
{
    # read grepWin config from registry
    $originalDir = $(Get-Location)
    Set-Location -Path Registry::HKEY_CURRENT_USER\SOFTWARE\grepWin

    # %path% -> $filepath, %line% -> $line
    $editorcmd = $(Get-ItemPropertyValue -Path . -Name "editorcmd")
    
    # directories
    $paths += $(Get-ItemPropertyValue -Path . -Name "searchpath")
    for ($i = 0; <# read until missing key #>; $i++) 
    {
        try 
        {
            $paths += $(Get-ItemPropertyValue -Path History -Name $("SearchPaths" + $i))
        }
        catch [System.Management.Automation.PSArgumentException]
        {
            break;
        }    
    }
    
    # filters
    for ($i = 0; <# read until missing key #>; $i++) 
    {
        try 
        {
            $iter = $(Get-ItemPropertyValue -Path History -Name $("FilePattern" + $i))
            $iter = $iter.replace("|", " ")
            $filters += $iter
        }
        catch [System.Management.Automation.PSArgumentException]
        {
            break;
        }    
    }

    # patterns
    $pattern = $(Get-ItemPropertyValue -Path . -Name "pattern")
    if ($pattern.Length -ne 0) { $patterns += $pattern }
    for ($i = 0; <# read until missing key #>; $i++) 
    {
        try 
        {
            $patterns += $(Get-ItemPropertyValue -Path History -Name $("SearchPattern" + $i))
        }
        catch [System.Management.Automation.PSArgumentException]
        {
            break;
        }    
    }

    Set-Location -Path $originalDir
}

# check for presets/bookmarks
$mightygrep_bookmarks = [System.Collections.ArrayList]::new()
$bookmarks_path = $($env:APPDATA + "\grepWin\bookmarks")
if (Test-Path -Path $bookmarks_path) {
    # ini file, section names are bookmark entries
    $global:entries = @{}
    $bookmark_names = [System.Collections.ArrayList]::new()
    $bookmark_name = ""
    foreach($line in Get-Content $bookmarks_path) {
        $left_bracket_index = $line.IndexOf('[')
        $right_bracket_index = $line.LastIndexOf(']')
        if (($left_bracket_index -eq 0) -and ($right_bracket_index -eq $line.Length - 1)) {
            $bookmark_name = $line.Substring($left_bracket_index + 1, $right_bracket_index - $left_bracket_index - 1)
            $bookmark_names.Add($bookmark_name)
        }
    
        $equal_index = $line.IndexOf('=')
        if ($equal_index -ne -1) {
            $key = $line.Substring(0, $equal_index)
            $value = $line.Substring($equal_index + 1)
            $global:entries.Add($bookmark_name + $key, $value)
        }
    }
    
    function GetEntry() {
        param ($bookmark_name, $entry_name)
        $fullname = $bookmark_name + $entry_name
        return $global:entries[$fullname]
    }
    
    # SearchFlag_PatternRegex         = 1
    # SearchFlag_FilterRegex          = 2
    # SearchFlag_PatternCaseSensitive = 4
    # SearchFlag_SearchNames          = 8
    # SearchFlag_FilterCaseSensitive  = 16
    # SearchFlag_FilterPath           = 32
    # SearchFlag_PatternExactWord     = 64
    # SearchFlag_DontRecursiveSearch  = 128
    # SearchFlag_SearchHidden         = 256
    # SearchFlag_SearchBinary         = 512
    foreach ($name in $bookmark_names) {
        $flags = 0
        if ("true" -eq $(GetEntry $name "useregex")) { $flags += 1 }
        if ("true" -eq $(GetEntry $name "filematchregex")) { $flags += 2 }
        if ("true" -eq $(GetEntry $name "casesensitive")) { $flags += 4 }
        # no equivalent for SearchFlag_SearchNames 8
        # no equivalent for SearchFlag_FilterCaseSensitive 16
        # no equivalent for SearchFlag_FilterPath 32
        if ("true" -eq $(GetEntry $name "wholewords")) { $flags += 64 }
        # no equivalent for SearchFlag_DontRecursiveSearch 128
        if ("true" -eq $(GetEntry $name "includehidden")) { $flags += 256 }
        if ("true" -eq $(GetEntry $name "includebinary")) { $flags += 512 }
        $sources = $(GetEntry $name "searchpath")
        $filters = $(GetEntry $name "filematch").replace("|", " ")
        $pattern = $(GetEntry $name "searchString")
    
        # remove strings surrrounded by double quotes
        $filters = $filters.Substring(1, $filters.Length - 2)
        $pattern = $pattern.Substring(1, $pattern.Length - 2)
    
        # make mightygrep bookmark entry
        $items = @(
            $name, $sources, $filters, $pattern, $flags,
            # min/max filesize
            0, 1099511627776,
    
            # filetimes aren't used
            0,0,0,0,0,0,0,
            0,0,0,0,0,0,0,
            0,0,0,0,0,0,0,
            0,0,0,0,0,0,0
        )
        $mightygrep_bookmarks.Add($items -join "`t")
    }
}

# create the new ini
# %path% -> $filepath, %line% -> $line
$editorcmd = $editorcmd.replace("%path%", "`$filepath")
$editorcmd = $editorcmd.replace("%line%", "`$line")
WriteLine $("ctrl_click_match_command = " + $editorcmd)

WriteLine "directory_history ="
foreach ($_ in $paths) { WriteLine $_ }
WriteLine ">`tLIST_END"
WriteLine ""

WriteLine "filter_history ="
foreach ($_ in $filters) { WriteLine $_ }
WriteLine ">`tLIST_END"
WriteLine ""

WriteLine "pattern_history ="
foreach ($_ in $patterns) { WriteLine $_ }
WriteLine ">`tLIST_END"
WriteLine ""

WriteLine "bookmarks ="
foreach ($_ in $mightygrep_bookmarks) { WriteLine $_ }
WriteLine ">`tLIST_END"
WriteLine ""
