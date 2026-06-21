$lines = Get-Content 'lib\screens\home_screen.dart'
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'withValues\(alpha: \)') {
        $next = if ($i + 1 -lt $lines.Count) { $lines[$i + 1] } else { '' }
        $val = '0.1'
        if     ($lines[$i] -match 'shadowColor')   { $val = '0.3'  }
        elseif ($lines[$i] -match 'primaryColor')  { $val = '0.40' }
        elseif ($lines[$i] -match 'dangerColor')   { $val = '0.8'  }
        elseif ($next      -match 'blurRadius: 8') { $val = '0.40' }
        elseif ($next      -match 'blurRadius: 3') { $val = '0.15' }
        elseif ($next      -match 'blurRadius: 6') { $val = '0.22' }
        elseif ($next      -match 'blurRadius: 2') { $val = '0.06' }
        elseif ($next      -match 'blurRadius: 10'){ $val = '0.12' }
        $lines[$i] = $lines[$i] -replace 'withValues\(alpha: \)', "withValues(alpha: $val)"
    }
}
Set-Content 'lib\screens\home_screen.dart' $lines -Encoding UTF8
Write-Host "Done! Fixed all broken withValues(alpha: ) entries."
