# Opens the report in Word, updates the table of contents and all fields,
# saves the .docx and exports a PDF next to it.
param([string]$Docx = (Join-Path $PSScriptRoot 'BCSE302P_Project_CampusBite.docx'))

$docx = (Resolve-Path $Docx).Path
$pdf = [IO.Path]::ChangeExtension($docx, '.pdf')
$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0
try {
  $doc = $word.Documents.Open($docx)
  $doc.Repaginate()
  foreach ($toc in $doc.TablesOfContents) { $toc.Update() }
  $doc.Fields.Update() | Out-Null
  foreach ($toc in $doc.TablesOfContents) { $toc.Update() }
  $doc.Save()
  $doc.ExportAsFixedFormat($pdf, 17)   # 17 = wdExportFormatPDF
  "pages: " + $doc.ComputeStatistics(2)
  $doc.Close()
} finally {
  $word.Quit()
}
"saved $pdf"
