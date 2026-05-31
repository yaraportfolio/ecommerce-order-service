#!/bin/sh
set -e

# --- CONFIGURATION INITIALE ---
SCAN_TYPE="${1:-fs}"
TARGET="${2:-.}"
OUTPUT_FILE="${3:-container-report.html}"

# Utilisation directe de la variable SERVICE passée par Jenkins
# On sépare les fichiers par type (fs vs image) pour éviter les courbes bizarres
STATS_FILE="${SCAN_TYPE}-${SERVICE}-statistiques.csv"

# Couleurs pour la console
RED=$(printf '\033[1;31m')
YELLOW=$(printf '\033[1;33m')
CYAN=$(printf '\033[1;36m')
RESET=$(printf '\033[0m')
BOLD=$(printf '\033[1m')

# Options Trivy
OPTS="--scanners vuln --severity MEDIUM,HIGH,CRITICAL"
[ "$SCAN_TYPE" = "fs" ] && OPTS="$OPTS --include-dev-deps=false"

# --- 1. CAPTURE DES DONNÉES (CONSOLE) ---
RAW_LOG=$(trivy $SCAN_TYPE "$TARGET" $OPTS --format template --template '
{{- $found := false -}}
{{- range . -}}
  {{- range .Vulnerabilities -}}
    {{- $found = true -}}
@SEV_{{.Severity}}@ ID: {{ .VulnerabilityID }}
 │ Package   : {{ .PkgName }}
 │ Installed : {{ .InstalledVersion }}
 └ Fixed in  : {{ default "N/A" .FixedVersion }}
----------------------------------------------------------------------
{{ printf "\n" }}
  {{- end -}}
{{- end -}}
{{- if not $found }}✅ No vulnerabilities found.{{- end }}')

VULN_LOG=$(echo "$RAW_LOG" | sed "s/@SEV_CRITICAL@/${RED}CRITICAL  ${RESET}/g; s/@SEV_HIGH@/${RED}HIGH      ${RESET}/g; s/@SEV_MEDIUM@/${YELLOW}MEDIUM    ${RESET}/g")

echo "${CYAN}${BOLD}┌────────────────────────────────────────────────────────────────────┐${RESET}"
echo "${CYAN}${BOLD}│            REPORTING DE SÉCURITÉ : ${SERVICE} ($SCAN_TYPE)          ${RESET}"
echo "${CYAN}${BOLD}└────────────────────────────────────────────────────────────────────┘${RESET}"
echo "$VULN_LOG"

# --- 2. GESTION DE L'HISTORIQUE (Version Corrigée) ---
# On calcule chaque valeur séparément
# On utilise tr -d '\n' pour supprimer tout retour à la ligne parasite
C_CRIT=$(echo "$RAW_LOG" | grep -c "@SEV_CRITICAL@" | tr -d '\n' || echo 0)
C_HIGH=$(echo "$RAW_LOG" | grep -c "@SEV_HIGH@" | tr -d '\n' || echo 0)
C_MED=$(echo "$RAW_LOG" | grep -c "@SEV_MEDIUM@" | tr -d '\n' || echo 0)

DATE_LABEL=$(date "+%d/%m %H:%M")

# On force l'écriture sur UNE SEULE LIGNE avec des valeurs par défaut
NEW_LINE=$(printf "%s,%s,%s,%s" "$DATE_LABEL" "$C_CRIT" "$C_HIGH" "$C_MED")

[ ! -f "$STATS_FILE" ] && echo "Date,Critique,High,Medium" > "$STATS_FILE"
echo "$NEW_LINE" >> "$STATS_FILE"

# Garder uniquement les 15 derniers builds
tail -n 16 "$STATS_FILE" > "${STATS_FILE}.tmp" && mv "${STATS_FILE}.tmp" "$STATS_FILE"

# Préparation des données pour Chart.js
LABELS=$(cut -d',' -f1 "$STATS_FILE" | grep -v "Date" | sed "s/.*/'&'/" | paste -sd, -)
D_CRIT=$(cut -d',' -f2 "$STATS_FILE" | grep -v "Critique" | paste -sd, -)
D_HIGH=$(cut -d',' -f3 "$STATS_FILE" | grep -v "High" | paste -sd, -)
D_MED=$(cut -d',' -f4 "$STATS_FILE" | grep -v "Medium" | paste -sd, -)

# --- 3. GÉNÉRATION DU RAPPORT HTML ---
trivy $SCAN_TYPE "$TARGET" $OPTS --format template --template "
<!DOCTYPE html>
<html lang='fr'>
<head>
    <meta charset='UTF-8'>
    <script src='https://cdn.jsdelivr.net/npm/chart.js'></script>
    <style>
        body { font-family: sans-serif; background-color: #f4f7f9; padding: 20px; }
        .container { max-width: 1000px; margin: auto; }
        .header { background: linear-gradient(135deg, #00acc1 0%, #007c91 100%); color: white; padding: 20px; border-radius: 12px; text-align: center; margin-bottom: 25px; }
        .chart-card { background: white; border-radius: 12px; padding: 20px; margin-bottom: 25px; height: 300px; box-shadow: 0 2px 10px rgba(0,0,0,0.05); }
        .card { background: white; border-radius: 8px; padding: 15px; margin-bottom: 12px; border-left: 8px solid #ccc; box-shadow: 0 2px 5px rgba(0,0,0,0.05); }
        .CRITICAL { border-left-color: #ff1744; } .HIGH { border-left-color: #ff9100; } .MEDIUM { border-left-color: #fbc02d; }
        .badge { display: inline-block; padding: 3px 10px; border-radius: 15px; color: white; font-size: 0.8em; font-weight: bold; margin-bottom: 8px; }
        .bg-CRITICAL { background-color: #ff1744; } .bg-HIGH { background-color: #ff9100; } .bg-MEDIUM { background-color: #fbc02d; color: #333; }
        .details { display: grid; grid-template-columns: 120px 1fr; gap: 5px; font-size: 0.9em; }
        .label { color: #7f8c8d; font-weight: 600; }
        .fix { color: #27ae60; font-weight: bold; }
    </style>
</head>
<body>
    <div class='container'>
        <div class='header'>
            <h1>🛡️ SECURITY DASHBOARD : ${SERVICE}</h1>
            {{ if gt (len .) 0 }}
              <p style='margin:10px 0 0; opacity:0.9;'>Cible : {{ (index . 0).Target }}</p>
            {{ else }}
              <p style='margin:10px 0 0; opacity:0.9;'>Cible : (aucune cible détectée)</p>
            {{ end }}
        </div>
        <div class='chart-card'><canvas id='trendChart'></canvas></div>
        
        {{- \$found := false -}}
        {{- range . -}}{{- range .Vulnerabilities -}}{{- \$found = true -}}
            <div class='card {{ .Severity }}'>
                <span class='badge bg-{{ .Severity }}'>{{ .Severity }}</span>
                <div style='font-weight: bold;'>{{ .VulnerabilityID }}</div>
                <div class='details'>
                    <div class='label'>Package:</div><div>{{ .PkgName }}</div>
                    <div class='label'>Installed:</div><div>{{ .InstalledVersion }}</div>
                    <div class='label'>Fix:</div><div class='fix'>{{ default \"N/A\" .FixedVersion }}</div>
                </div>
            </div>
        {{- end -}}{{- end -}}
        {{- if not \$found -}}<div style='text-align:center; padding:40px;'>✨ Aucune vulnérabilité détectée.</div>{{- end -}}
    </div>
    <script>
        new Chart(document.getElementById('trendChart'), {
            type: 'line',
            data: {
                labels: [$LABELS],
                datasets: [
                    { label: 'Critical', data: [$D_CRIT], borderColor: '#ff1744', backgroundColor: 'transparent', fill: false, tension: 0.3 },
                    { label: 'High', data: [$D_HIGH], borderColor: '#ff9100', backgroundColor: 'transparent', fill: false, tension: 0.3 },
                    { label: 'Medium', data: [$D_MED], borderColor: '#fbc02d', backgroundColor: 'transparent', fill: false, tension: 0.3 }
                ]
            },
            options: { 
                responsive: true, maintainAspectRatio: false,
                scales: { y: { beginAtZero: true, ticks: { stepSize: 1, precision: 0 } } }
            }
        });
    </script>
</body>
</html>" > "$OUTPUT_FILE"

echo "✅ Rapport $SCAN_TYPE terminé pour $SERVICE."