name: Automated MT5 Trading Session

on:
  workflow_dispatch: # Allows 1-tap start from phone

jobs:
  launch-trader:
    runs-on: windows-latest
    timeout-minutes: 240

    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Install MT5 Silently
        run: |
          Write-Host "Downloading MT5 installer..."
          Invoke-WebRequest -Uri "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe" -OutFile "mt5setup.exe"
          Write-Host "Installing MT5..."
          Start-Process -FilePath ".\mt5setup.exe" -ArgumentList "/auto" -Wait
          Start-Sleep -Seconds 10

      - name: Find, Copy & Compile EA via Cloud CLI
        run: |
          Write-Host "Locating InstitutionalAlgoEA.mq5..."
          $eaPath = Get-ChildItem -Recurse -Filter "InstitutionalAlgoEA.mq5" | Select-Object -ExpandProperty FullName -First 1
          
          if (-not $eaPath) {
            Write-Error "InstitutionalAlgoEA.mq5 not found in repository!"
            exit 1
          }
          
          Write-Host "Found EA at: $eaPath"
          Copy-Item -Path $eaPath -Destination "C:\Program Files\MetaTrader 5\MQL5\Experts\InstitutionalAlgoEA.mq5" -Force

          Write-Host "Compiling EA to .ex5..."
          & "C:\Program Files\MetaTrader 5\metaeditor64.exe" /compile:"C:\Program Files\MetaTrader 5\MQL5\Experts\InstitutionalAlgoEA.mq5" /log:"C:\Program Files\MetaTrader 5\compile.log"
          
          Start-Sleep -Seconds 5
          if (Test-Path "C:\Program Files\MetaTrader 5\compile.log") {
            Get-Content "C:\Program Files\MetaTrader 5\compile.log"
          }

      - name: Generate Login Config
        env:
          EXNESS_LOGIN: ${{ secrets.EXNESS_LOGIN }}
          EXNESS_PASSWORD: ${{ secrets.EXNESS_PASSWORD }}
          EXNESS_SERVER: ${{ secrets.EXNESS_SERVER }}
        run: |
          $configContent = @"
          [Common]
          Login=$env:EXNESS_LOGIN
          Password=$env:EXNESS_PASSWORD
          Server=$env:EXNESS_SERVER

          [Experts]
          Enabled=1
          Account=$env:EXNESS_LOGIN
          AllowDLL=0

          [Start]
          Symbol=XAUUSD
          Period=M5
          Expert=InstitutionalAlgoEA
          "@
          Set-Content -Path "C:\Program Files\MetaTrader 5\startup.ini" -Value $configContent

      - name: Run Bot Session
        run: |
          Write-Host "Starting MT5 and running bot session..."
          Start-Process -FilePath "C:\Program Files\MetaTrader 5\terminal64.exe" -ArgumentList "/portable /config:startup.ini"
          
          # Keeps runner active for 3.5 hours
          Start-Sleep -Seconds 12600

      - name: Session Finished
        run: |
          Write-Host "Session complete. Closing terminal..."
          Stop-Process -Name "terminal64" -Force -ErrorAction SilentlyContinue