<#
.SYNOPSIS
  Confere, contra o YouTube de verdade, as suposições da busca por canal do Sonora.

.DESCRIPTION
  Roda os MESMOS comandos do yt-dlp que o app roda (YoutubeClient.search,
  getChannelVideos, getChannelAlbums, getAlbumTracks) e diz, linha a linha,
  se o que o código do Sonora assume é verdade: se a busca traz channel_id /
  channel_url / view_count, se cada aba do canal (/videos, /streams,
  /releases, /playlists, /search) responde, se o avatar vem em "thumbnails"
  etc.  É só leitura: não baixa nenhuma música.

  Rode ISTO antes de confiar na feature — foi escrita sem acesso ao YouTube.

.PARAMETER Query
  Busca de teste (padrão: "imagine dragons").

.PARAMETER YtDlp
  Caminho do yt-dlp.exe. Padrão: ..\assets\bin\yt-dlp.exe (relativo a este script).

.PARAMETER ChannelId
  Opcional: força um canal (UC...) em vez de usar o canal mais frequente da busca.

.PARAMETER SalvarDumps
  Salva o JSON cru de cada comando em tools\dumps-verificacao\ — útil pra
  mandar de volta e ajustar o código com base no formato real.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\verificar_canal_ytdlp.ps1
  powershell -ExecutionPolicy Bypass -File tools\verificar_canal_ytdlp.ps1 -Query "legiao urbana" -SalvarDumps
#>
param(
  [string]$Query = 'imagine dragons',
  [string]$YtDlp = '',
  [string]$ChannelId = '',
  [switch]$SalvarDumps
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if (-not $YtDlp) { $YtDlp = Join-Path $PSScriptRoot '..\assets\bin\yt-dlp.exe' }
if (-not (Test-Path $YtDlp)) {
  Write-Host "yt-dlp não encontrado em: $YtDlp (use -YtDlp para indicar o caminho)" -ForegroundColor Red
  exit 1
}
$script:YtDlpPath = (Resolve-Path $YtDlp).Path
$script:Falhas = 0
$script:DumpDir = Join-Path $PSScriptRoot 'dumps-verificacao'
if ($SalvarDumps -and -not (Test-Path $script:DumpDir)) { New-Item -ItemType Directory -Path $script:DumpDir | Out-Null }

function ConvertTo-QuotedArg([string]$Arg) { '"' + ($Arg -replace '"', '\"') + '"' }

# Roda o yt-dlp como processo, com stdout/stderr em UTF-8 (igual ao app).
function Invoke-YtDlp {
  param([string[]]$YtArgs)
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $script:YtDlpPath
  $psi.Arguments = (($YtArgs | ForEach-Object { ConvertTo-QuotedArg $_ }) -join ' ')
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
  $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
  $psi.CreateNoWindow = $true
  $psi.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8'
  $psi.EnvironmentVariables['PYTHONUTF8'] = '1'
  $proc = [System.Diagnostics.Process]::Start($psi)
  $outTask = $proc.StandardOutput.ReadToEndAsync()
  $errTask = $proc.StandardError.ReadToEndAsync()
  $proc.WaitForExit()
  [pscustomobject]@{ ExitCode = $proc.ExitCode; StdOut = $outTask.Result; StdErr = $errTask.Result }
}

# O mesmo comando de YoutubeClient._dumpFlatPlaylistJson.
function Get-FlatDump {
  param([string]$Url, [int]$Limit, [string]$DumpName)
  $r = Invoke-YtDlp @('--flat-playlist', '--yes-playlist', '--playlist-end', "$Limit", '--dump-single-json', $Url)
  $json = $null
  if ($r.ExitCode -eq 0 -and $r.StdOut.Trim().Length -gt 0) {
    if ($SalvarDumps -and $DumpName) { Set-Content -Path (Join-Path $script:DumpDir "$DumpName.json") -Value $r.StdOut -Encoding UTF8 }
    $json = $r.StdOut | ConvertFrom-Json
  }
  [pscustomobject]@{ ExitCode = $r.ExitCode; StdErr = $r.StdErr.Trim(); Json = $json }
}

function Test-Has($Obj, [string]$Name) {
  $prop = $Obj.PSObject.Properties[$Name]
  ($null -ne $prop) -and ($null -ne $prop.Value) -and ("$($prop.Value)" -ne '')
}

function Write-Check([bool]$Ok, [string]$Text) {
  if ($Ok) { Write-Host "  [OK]    $Text" -ForegroundColor Green }
  else { Write-Host "  [FALHA] $Text" -ForegroundColor Red; $script:Falhas++ }
}

function Get-Entries($Dump) {
  if ($null -eq $Dump.Json -or $null -eq $Dump.Json.entries) { return @() }
  return @($Dump.Json.entries)
}

# Roda uma aba e imprime o que o app precisa saber dela.
function Test-Tab {
  param(
    [string]$Title, [string]$Url, [int]$Limit, [string]$DumpName,
    [switch]$SemArte,     # playlist de álbum não tem avatar/banner de canal: não cobrar
    [switch]$TemPlanoB    # se falhar, o app cai num plano B (não é erro para o usuário)
  )
  Write-Host ''
  Write-Host $Title -ForegroundColor Cyan
  Write-Host "  URL: $Url"
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $d = Get-FlatDump -Url $Url -Limit $Limit -DumpName $DumpName
  $sw.Stop()
  Write-Host ("  Tempo: {0:N1}s" -f $sw.Elapsed.TotalSeconds)

  if ($d.ExitCode -ne 0) {
    $lines = @($d.StdErr -split "`n" | Where-Object { $_.Trim() })
    $last = if ($lines.Count -gt 0) { $lines[$lines.Count - 1] } else { '(sem mensagem)' }
    $lower = $d.StdErr.ToLower()
    if ($lower.Contains('does not have a') -and $lower.Contains('tab')) {
      Write-Host "  [INFO]  yt-dlp saiu com código $($d.ExitCode): $last" -ForegroundColor Yellow
      Write-Host "          O app trata isto como 'o canal não tem esta aba' (lista vazia, sem erro). Normal para canais sem esta aba." -ForegroundColor Yellow
    } elseif ($TemPlanoB) {
      Write-Host "  [AVISO] yt-dlp saiu com código $($d.ExitCode): $last" -ForegroundColor Yellow
      Write-Host "          O app cai para o plano B desta aba (ver abaixo) — não aparece erro para o usuário." -ForegroundColor Yellow
    } else {
      Write-Host "  [FALHA] yt-dlp saiu com código $($d.ExitCode): $last" -ForegroundColor Red
      Write-Host "          O app trata isto como ERRO (mostra 'Não foi possível carregar')." -ForegroundColor Yellow
      $script:Falhas++
    }
    return $d
  }

  $entries = Get-Entries $d
  Write-Host "  Entradas: $($entries.Count)"
  $thumbs = @()
  if ($null -ne $d.Json.thumbnails) { $thumbs = @($d.Json.thumbnails) }
  $hasAvatar = @($thumbs | Where-Object { "$($_.id)" -like '*avatar*' }).Count -gt 0
  $hasBanner = @($thumbs | Where-Object { "$($_.id)" -like '*banner*' }).Count -gt 0
  if (-not $SemArte) {
    Write-Check $hasAvatar "avatar do canal em thumbnails do nível de cima (id com 'avatar')"
    Write-Check $hasBanner "banner do canal em thumbnails do nível de cima (id com 'banner')"
  }
  $entries | Select-Object -First 5 | ForEach-Object {
    Write-Host ("  - {0} | views={1} | ie_key={2}" -f $_.title, $_.view_count, $_.ie_key)
  }
  return $d
}

# ---------------------------------------------------------------- 1) busca
Write-Host "1) Busca: ytsearch10:$Query   (mesmo comando de YoutubeClient.search)" -ForegroundColor Cyan
$search = Invoke-YtDlp @('--flat-playlist', '--dump-single-json', "ytsearch10:$Query")
if ($search.ExitCode -ne 0) {
  Write-Host "  [FALHA] a busca falhou (código $($search.ExitCode)):" -ForegroundColor Red
  Write-Host $search.StdErr
  exit 2
}
if ($SalvarDumps) { Set-Content -Path (Join-Path $script:DumpDir 'busca.json') -Value $search.StdOut -Encoding UTF8 }
$entries = @(($search.StdOut | ConvertFrom-Json).entries)
$n = $entries.Count
Write-Host "  $n resultados"
$minimo = [math]::Ceiling($n * 0.8)
foreach ($campo in @('channel', 'channel_id', 'channel_url', 'view_count')) {
  $qtd = @($entries | Where-Object { Test-Has $_ $campo }).Count
  Write-Check ($n -gt 0 -and $qtd -ge $minimo) "'$campo' preenchido em $qtd de $n resultados"
}
$entries | Select-Object -First 5 | ForEach-Object {
  Write-Host ("  - {0} | canal={1} | {2} | views={3}" -f $_.title, $_.channel, $_.channel_id, $_.view_count)
}

if (-not $ChannelId) {
  $top = $entries | Where-Object { Test-Has $_ 'channel_id' } | Group-Object channel_id | Sort-Object Count -Descending | Select-Object -First 1
  if ($null -eq $top) {
    Write-Host '  Sem channel_id nos resultados — não dá para testar as abas. Use -ChannelId UC... para forçar um canal.' -ForegroundColor Red
    exit 3
  }
  $ChannelId = $top.Name
  $nome = ($top.Group | Select-Object -First 1).channel
  Write-Host "  Canal do card (aprox.: o mais frequente): $nome  [$ChannelId]  — $($top.Count) resultado(s)"
}
$base = "https://www.youtube.com/channel/$ChannelId"

# ------------------------------------------------------------ 2) Músicas
$videos = Test-Tab "2) Aba Músicas: $base/videos  (o app lê 90 e ordena por view_count)" "$base/videos" 90 'videos'
$vEntries = Get-Entries $videos
if ($vEntries.Count -gt 0) {
  $comViews = @($vEntries | Where-Object { Test-Has $_ 'view_count' }).Count
  Write-Check ($comViews -ge [math]::Ceiling($vEntries.Count * 0.8)) "view_count preenchido em $comViews de $($vEntries.Count) vídeos (necessário para ordenar por popularidade)"
  $maisVistos = $vEntries | Where-Object { Test-Has $_ 'view_count' } | Sort-Object { [double]$_.view_count } -Descending | Select-Object -First 5
  Write-Host '  Top 5 que o app mostraria (ordenado localmente por views):'
  $maisVistos | ForEach-Object { Write-Host ("    * {0}  ({1} views)" -f $_.title, $_.view_count) }
}

# O comando LEVE que o app usa na busca para pegar o logo do canal do card
# (YoutubeClient.getChannelArt): só 1 vídeo, mas o avatar tem que vir igual.
[void](Test-Tab "2c) Logo do canal para o card da busca: $base/videos com --playlist-end 1" "$base/videos" 1 'avatar-card')

# Experimento: a ordenação "Popular" do próprio YouTube.
$pop = Test-Tab "2b) EXPERIMENTO — ordenação 'Popular' do YouTube: $base/videos?view=0&sort=p" "$base/videos?view=0&sort=p" 30 'videos-popular'
$pEntries = Get-Entries $pop
if ($pEntries.Count -gt 0 -and $vEntries.Count -gt 0) {
  $maxLocal = ($vEntries | Where-Object { Test-Has $_ 'view_count' } | Measure-Object -Property view_count -Maximum).Maximum
  $primeiro = $pEntries[0].view_count
  if ($null -ne $primeiro -and $null -ne $maxLocal -and [double]$primeiro -gt [double]$maxLocal) {
    Write-Host "  [INFO]  sort=p trouxe um vídeo MAIS visto ($primeiro) que todos os 90 recentes ($maxLocal): parece FUNCIONAR — vale trocar o endereço em YoutubeClient._getChannelSongs." -ForegroundColor Yellow
  } else {
    Write-Host "  [INFO]  sort=p não trouxe nada mais visto que os 90 recentes: provavelmente é ignorado (ou o canal é pequeno). Mantenha a ordenação local." -ForegroundColor Yellow
  }
}

# --------------------------------------------------------------- 3) Ao vivo
[void](Test-Tab "3) Aba Ao vivo: $base/streams" "$base/streams" 40 'streams')

# ---------------------------------------------------------------- 4) Álbuns
$rel = Test-Tab "4) Aba Álbuns: $base/releases" "$base/releases" 60 'releases'
$albumSrc = $rel
$relAlbuns = @(Get-Entries $rel | Where-Object { $_.ie_key -eq 'YoutubeTab' -or "$($_.url)" -like '*list=*' })
if ($rel.ExitCode -eq 0) {
  Write-Check ($relAlbuns.Count -gt 0) "/releases trouxe $($relAlbuns.Count) entrada(s) que parecem playlists (ie_key=YoutubeTab ou url com list=)"
}
if ($relAlbuns.Count -eq 0) {
  $pl = Test-Tab "4b) Plano B de Álbuns: $base/playlists" "$base/playlists" 60 'playlists'
  $albumSrc = $pl
  $relAlbuns = @(Get-Entries $pl | Where-Object { $_.ie_key -eq 'YoutubeTab' -or "$($_.url)" -like '*list=*' })
}

# ------------------------------------------------- 5) Faixas de um álbum
if ($relAlbuns.Count -gt 0) {
  $album = $relAlbuns[0]
  $albumUrl = if ("$($album.url)" -like 'http*') { $album.url } else { "https://www.youtube.com/playlist?list=$($album.id)" }
  $faixas = Test-Tab "5) Faixas do 1º álbum '$($album.title)': $albumUrl" $albumUrl 100 'album-faixas' -SemArte
  $fEntries = Get-Entries $faixas
  # Capa do álbum = miniatura do 1º vídeo (YoutubeClient.getAlbumCoverUrl): 1 item só.
  $capa = Test-Tab "5b) Capa do álbum = 1º vídeo, lendo só 1 item: $albumUrl com --playlist-end 1" $albumUrl 1 'album-capa' -SemArte
  $capaEntries = Get-Entries $capa
  if ($capaEntries.Count -gt 0) {
    $primeiro = $capaEntries[0]
    # Cuidado: @($null).Count vale 1 no PowerShell — por isso o teste de $null antes.
    $listaMiniaturas = $primeiro.thumbnails
    $temMiniatura = (Test-Has $primeiro 'thumbnail') -or (($null -ne $listaMiniaturas) -and (@($listaMiniaturas).Count -gt 0))
    Write-Check ($capaEntries.Count -eq 1) "--playlist-end 1 devolveu exatamente 1 faixa (devolveu $($capaEntries.Count))"
    if ($temMiniatura) {
      Write-Check $true '1ª faixa traz miniatura (thumbnails/thumbnail)'
    } else {
      Write-Host "  [INFO]  1ª faixa SEM miniatura no JSON — o app monta https://i.ytimg.com/vi/$($primeiro.id)/hqdefault.jpg a partir do ID (funciona para qualquer vídeo)." -ForegroundColor Yellow
    }
  }
  if ($fEntries.Count -gt 0) {
    $comCanal = @($fEntries | Where-Object { Test-Has $_ 'channel' -or (Test-Has $_ 'uploader') }).Count
    Write-Host "  Faixas: $($fEntries.Count)  (com nome de canal/uploader: $comCanal — as sem nome herdam o do artista)"
  }
} else {
  Write-Host ''
  Write-Host '5) Faixas de álbum: pulado (nenhum álbum encontrado acima).' -ForegroundColor Yellow
}

# ------------------------------------------------------------------ 6) Shows
$q = [uri]::EscapeDataString('full concert show completo').Replace('%20', '+')
$shows = Test-Tab "6) Aba Shows (busca DENTRO do canal): $base/search?query=$q" "$base/search?query=$q" 30 'shows' -TemPlanoB
if ($shows.ExitCode -ne 0) {
  # Plano B do app (YoutubeClient._getChannelShows): busca geral + filtro pelo canal.
  $nomeCanal = if ($nome) { $nome } else { $ChannelId }
  Write-Host "  Plano B: ytsearch40:$nomeCanal full concert show completo, filtrando channel_id = $ChannelId" -ForegroundColor Cyan
  $b = Invoke-YtDlp @('--flat-playlist', '--dump-single-json', "ytsearch40:$nomeCanal full concert show completo")
  if ($b.ExitCode -eq 0) {
    $todos = @(($b.StdOut | ConvertFrom-Json).entries)
    $doCanal = @($todos | Where-Object { "$($_.channel_id)" -eq $ChannelId })
    Write-Check ($doCanal.Count -gt 0) "plano B achou $($doCanal.Count) de $($todos.Count) resultado(s) do próprio canal"
    $doCanal | Select-Object -First 5 | ForEach-Object { Write-Host ("    * {0}" -f $_.title) }
  } else {
    Write-Check $false 'o plano B (busca geral) também falhou'
  }
}

# ------------------------------------------------------------------ resumo
Write-Host ''
if ($script:Falhas -eq 0) {
  Write-Host 'RESUMO: todas as suposições conferiram.' -ForegroundColor Green
} else {
  Write-Host "RESUMO: $($script:Falhas) verificação(ões) falharam — veja as linhas [FALHA] acima e a seção 'Se uma verificação falhar' do LEIA-ME-busca-canal.md." -ForegroundColor Red
}
if ($SalvarDumps) { Write-Host "JSONs salvos em: $($script:DumpDir)" }
