# convert baregrep/baregreppro configuration settings to mightygrep
# reads from registry or a filename ending with .udm extension in the script's directory

$outfile = $(Join-Path $(Get-Location) "mightygrep.ini")
if (Test-Path $outfile) {
    Clear-Content -Path $outfile
}

function WriteLine {
    param ( $Line )
    echo $Line
    echo $Line | Out-File -FilePath $outfile -Append -Encoding utf8
}

function WriteConfigString {
    param ( $key, $value )
    WriteLine $($key + " = " + $value)
}

function WriteConfigBool {
    param ( $key, $value )
    $value = if ($value -eq $true) { "1" } else { "0" }
    WriteConfigString $key $value
}

function GetUTF8 {
    # convert ANSI -> UTF8
    param ( $byte_array)
    [System.Text.Encoding]::Default.GetString($byte_array)
}

$global:udm_fpos = 0
[byte[]] $global:udm_bytes = $(Get-ChildItem -Filter *.udm | Get-Content -Encoding Byte)
if ($global:udm_bytes.Length -eq 0)
{
    [byte[]] $global:udm_bytes = $(Get-ItemPropertyValue -Path "Registry::HKEY_CURRENT_USER\SOFTWARE\Bare Metal Software\BareGrepPro\1.0" -Name "Persistent Data")
    if ($global:udm_bytes.Length -eq 0)
    {
        [byte[]] $global:udm_bytes = $(Get-ItemPropertyValue -Path "Registry::HKEY_CURRENT_USER\SOFTWARE\Bare Metal Software\BareGrep\1.1" -Name "Persistent Data")
        if ($global:udm_bytes.Length -eq 0)
        {
            echo "Couldn't find BareGrep registry or *.udm!"
            exit 1
        }
    }
}

function ReadU8 {
    $result = $global:udm_bytes[$global:udm_fpos]
    $global:udm_fpos += 1
    return $result
}

function ReadU16 {
    $b0 = ReadU8
    $b1 = ReadU8
    $b1 * 256 + $b0
}

function ReadU32 {
    $w0 = ReadU16
    $w1 = ReadU16
    $w1 * 65536 + $w0
}

function SetFilePos {
    param( $fp )
    $global:udm_fpos = $fp
}

function GetFilePos {
    $global:udm_fpos
}

function ReadBytes {
    param( $n )
    $end = $global:udm_fpos + $n - 1
    $result = $global:udm_bytes[$global:udm_fpos .. $end]
    SetFilePos $end
    return $result
}

function ProcessRecord {
    param( $offset_to_record )
    $saved_fpos = GetFilePos
    SetFilePos $offset_to_record

    # read the udm record, 8 byte aligned
    $type = ReadU16
    $pad = ReadU16
    #echo $type
    #echo $pad

    switch ($type) {
        2 {
            # UInt32
            $result = ReadU32
        }
        3 {
            # Int32
            $result = ReadU32
        }
        4 {
            # boolean
            $val = ReadU32
            $result = $val -eq 4294967295 # 0xFFFFFFFF
        }
        6 {
            # byte array
            $num_bytes = ReadU32
            #echo $num_bytes
            $result = $(ReadBytes $num_bytes)
        }
        7 {
            # offset to record
            $record_off = ReadU32
            $result = ProcessRecord $record_off
        }
        8 {
            # array of uint32 data offsets
            $num_offsets = ReadU32
            $off_buffer_record_off = ReadU32
            $off_buffer = ProcessRecord $off_buffer_record_off
            $result = @()
            for ($i = 0; $($i + 4) -le $off_buffer.Length; $i += 4) {
                $iter_offset = [bitconverter]::ToUInt32($off_buffer,$i)
                if ($iter_offset -ne 0) {
                    $result += ,$(ProcessRecord $iter_offset)
                }
            }
        }
        9 {
            # name value pair, optional offset to next
            $name_off = ReadU32
            $value_off = ReadU32
            $next_off = ReadU32
            $name = GetUTF8 $(ProcessRecord $name_off)
            $value = ProcessRecord $value_off
            if ($next_off -ne 0) {
                ProcessRecord $next_off
            }

            if ($name -eq "FONT") {
                $b0 = $value[0]
                if ($b0 -eq 0xF5) { $fontsize = 8  }
                if ($b0 -eq 0xF4) { $fontsize = 9  }
                if ($b0 -eq 0xF3) { $fontsize = 10 }
                if ($b0 -eq 0xF1) { $fontsize = 11 }
                if ($b0 -eq 0xF0) { $fontsize = 12 }
                if ($b0 -eq 0xED) { $fontsize = 14 }
                if ($b0 -eq 0xEB) { $fontsize = 16 }
                if ($b0 -eq 0xE8) { $fontsize = 18 }
                if ($b0 -eq 0xE5) { $fontsize = 20 }
                if ($b0 -eq 0xE0) { $fontsize = 24 }
                WriteConfigString "font_size" $fontsize
                for ($off = 0x1C; ;$off += 1) {
                    if ($value[$off] -eq 0) {
                        $fontname = GetUTF8 $value[0x1C .. $($off - 1)]
                        WriteConfigString "font_face" $fontname
                        break
                    }
                }
            }
            elseif ($name -eq "INCREMENTAL SEARCH") {
                WriteConfigBool "incremental_search" $value
            }
            elseif ($name -eq "RECENT FOLDERS") {
                WriteLine "directory_history ="
                foreach ($_ in $value) { WriteLine $(GetUTF8 $_) }
                WriteLine ">`tLIST_END"
            }
            elseif ($name -eq "RECENT FILES") {
                WriteLine "filter_history ="
                foreach ($_ in $value) { WriteLine $(GetUTF8 $_) }
                WriteLine ">`tLIST_END"
            }
            elseif ($name -eq "TEXT SEARCHES") {
                WriteLine "pattern_history ="
                foreach ($iter in $value) {
                    #WriteLine $(GetUTF8 $iter[0])   # Name
                    WriteLine $(GetUTF8 $iter[1])    # text
                    #echo $iter[2]                   # text boolean regex
                    #echo $iter[3]                   # text boolean ignore case 
                    #echo $iter[4]                   # text boolean invert match
                }
                WriteLine ">`tLIST_END"
            }
            elseif ($name -eq "MAX RECENT FILES") {
                #WriteConfigString "max_file_history" $value
            }
        }
        0xB {
            $dw0 = ReadU32
            $dw1 = ReadU32
            $offset_to_pairs = ReadU32
            $offsets = $(ProcessRecord $offset_to_pairs)
            for ($i = 0; $($i + 4) -le $offsets.Length; $i += 4) {
                $iter_offset = [bitconverter]::ToUInt32($offsets,$i)
                if ($iter_offset -ne 0) {
                    ProcessRecord $iter_offset 
                }
            }
        }
    }

    SetFilePos($saved_fpos)
    return $result
}

ProcessRecord 0x10
exit 0
