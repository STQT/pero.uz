param(
    [string]$Url = "https://billboard.mediabaza.uz/updates/billboard-2.1.0.zip",
    [string]$Output = "billboard-2.1.0.zip"
)

Write-Host "=== Надёжная загрузка файла с поддержкой докачки ===" -ForegroundColor Cyan
Write-Host "URL: $Url"
Write-Host "Файл: $Output"
Write-Host ""

# --- Функция получения размера файла на сервере ---
function Get-RemoteFileSize {
    try {
        $r = Invoke-WebRequest -Uri $Url -Method Head -ErrorAction Stop
        return [int64]$r.Headers["Content-Length"]
    } catch {
        Write-Host "Ошибка получения размера файла: $_" -ForegroundColor Red
        exit
    }
}

# --- Получаем размер удалённого файла ---
$RemoteSize = Get-RemoteFileSize
Write-Host "Размер файла на сервере: $RemoteSize байт"

# --- Проверяем локальный файл ---
if (Test-Path $Output) {
    $LocalSize = (Get-Item $Output).Length
    Write-Host "Локальный файл найден ($LocalSize байт)" -ForegroundColor Yellow
} else {
    $LocalSize = 0
    Write-Host "Локального файла нет — начинаем загрузку с нуля"
}

# --- Проверка: уже загружен? ---
if ($LocalSize -eq $RemoteSize) {
    Write-Host "`n✔ Файл уже полностью скачан." -ForegroundColor Green
    exit
}

# --- Формируем Range заголовок ---
$Range = "bytes=$LocalSize-"
Write-Host "`nЗапрашиваем оставшуюся часть: $Range" -ForegroundColor Cyan

# --- Настраиваем поток для дозаписи ---
$client = New-Object System.Net.Http.HttpClient
$client.Timeout = [TimeSpan]::FromHours(5)
$request = New-Object System.Net.Http.HttpRequestMessage("GET", $Url)
$request.Headers.Range = New-Object System.Net.Http.Headers.RangeHeaderValue($LocalSize, $null)

$response = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result

if ($response.StatusCode -ne 206 -and $LocalSize -gt 0) {
    Write-Host "Сервер не поддерживает докачку (нет 206 Partial Content)." -ForegroundColor Red
    exit
}

# --- Открываем поток для записи ---
$stream = $response.Content.ReadAsStreamAsync().Result
$fs = [System.IO.File]::Open($Output, [System.IO.FileMode]::Append)

# --- Буфер 1 MB ---
$buffer = New-Object byte[] (1024*1024)
$totalRead = $LocalSize

Write-Host "`nНачинаем загрузку..."

while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
    $fs.Write($buffer, 0, $read)
    $totalRead += $read
    $percent = [math]::Round(($totalRead / $RemoteSize) * 100, 2)
    Write-Host "Загружено: $totalRead / $RemoteSize  ($percent%)" -NoNewline
    Write-Host "`r" -NoNewline
}

$fs.Close()
$stream.Close()
$client.Dispose()

Write-Host "`n`n✔ Загрузка завершена!" -ForegroundColor Green