#!/bin/sh
set -e

SCAN_TYPE="${1:-fs}"
TARGET="${2:-.}"
OUTPUT_FILE="${3:-dependency-report.html}"

# Couleurs ANSI Premium
RED=$(printf '\033[1;31m')
YELLOW=$(printf '\033[1;33m')
CYAN=$(printf '\033[1;36m')
RESET=$(printf '\033[0m')
BOLD=$(printf '\033[1m')

OPTS="--scanners vuln --severity MEDIUM,HIGH,CRITICAL"
[ "$SCAN_TYPE" = "fs" ] && OPTS="$OPTS --include-dev-deps=false"

# 1. Génération du template avec des ancres précises
trivy $SCAN_TYPE "$TARGET" $OPTS \
  --format template \
  --template '
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
{{- if not $found }}✅ No vulnerabilities found.{{- end }}' > security_log.txt

# 2. Remplacement chirurgical pour un alignement parfait
# Note: On ajoute des espaces pour que chaque label (CRITICAL/HIGH/MEDIUM) occupe 10 caractères
sed -i "s/@SEV_CRITICAL@/${RED}CRITICAL  ${RESET}/g" security_log.txt
sed -i "s/@SEV_HIGH@/${RED}HIGH      ${RESET}/g" security_log.txt
sed -i "s/@SEV_MEDIUM@/${YELLOW}MEDIUM    ${RESET}/g" security_log.txt

# 3. Affichage du Dashboard
echo "${CYAN}${BOLD}┌────────────────────────────────────────────────────────────────────┐${RESET}"
echo "${CYAN}${BOLD}│                REPORTING DE SÉCURITÉ : VULNÉRABILITÉS              │${RESET}"
echo "${CYAN}${BOLD}└────────────────────────────────────────────────────────────────────┘${RESET}"
cat security_log.txt

trivy $SCAN_TYPE "$TARGET" $OPTS \
  --format template \
  --template '
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; background-color: #f0f2f5; margin: 0; padding: 20px; }
        .container { max-width: 900px; margin: auto; }
        .header { background: linear-gradient(135deg, #00acc1 0%, #007c91 100%); color: white; padding: 30px; border-radius: 12px; text-align: center; box-shadow: 0 4px 15px rgba(0,0,0,0.1); margin-bottom: 30px; }
        .card { background: white; border-radius: 10px; padding: 20px; margin-bottom: 15px; box-shadow: 0 2px 8px rgba(0,0,0,0.05); display: flex; flex-direction: column; border-left: 8px solid #ccc; position: relative; }
        .CRITICAL { border-left-color: #ff1744; }
        .HIGH { border-left-color: #ff9100; }
        .MEDIUM { border-left-color: #ffea00; }
        .badge { display: inline-block; padding: 4px 12px; border-radius: 20px; color: white; font-size: 0.85em; font-weight: bold; text-transform: uppercase; width: fit-content; margin-bottom: 10px; }
        .bg-CRITICAL { background-color: #ff1744; }
        .bg-HIGH { background-color: #ff9100; }
        .bg-MEDIUM { background-color: #fbc02d; color: #333; }
        .cve-id { font-size: 1.2em; font-weight: bold; color: #2c3e50; margin-bottom: 10px; }
        .details { display: grid; grid-template-columns: 120px 1fr; gap: 8px; font-size: 0.95em; }
        .label { color: #7f8c8d; font-weight: 600; }
        .fix-version { color: #27ae60; font-weight: bold; }
        .no-vuln { text-align: center; padding: 50px; background: white; border-radius: 12px; color: #27ae60; font-size: 1.5em; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1 style="margin:0;">🛡️ RAPPORT DE SÉCURITÉ</h1>
            {{ if gt (len .) 0 }}
              <p style="margin:10px 0 0; opacity:0.9;">Cible : {{ (index . 0).Target }}</p>
            {{ else }}
              <p style="margin:10px 0 0; opacity:0.9;">Cible : (aucune cible détectée)</p>
            {{ end }}
        </div>
        
        {{- $found := false -}}
        {{- range . -}}
            {{- range .Vulnerabilities -}}
                {{- $found = true -}}
                <div class="card {{ .Severity }}">
                    <span class="badge bg-{{ .Severity }}">{{ .Severity }}</span>
                    <div class="cve-id">{{ .VulnerabilityID }}</div>
                    <div class="details">
                        <div class="label">Paquet :</div> <div>{{ .PkgName }}</div>
                        <div class="label">Installé :</div> <div>{{ .InstalledVersion }}</div>
                        <div class="label">Correction :</div> <div class="fix-version">{{ default "Non disponible" .FixedVersion }}</div>
                    </div>
                </div>
            {{- end -}}
        {{- end -}}
        
        {{- if not $found -}}
            <div class="no-vuln">✨ Félicitations ! Aucune vulnérabilité détectée.</div>
        {{- end -}}
    </div>
</body>
</html>' > "$OUTPUT_FILE"

echo "✅ Rapport HTML généré avec succès dans $OUTPUT_FILE"