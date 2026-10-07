$lstSeries = '39885,39676,39679,39588,39800,33532,34955,35831,39694,39099,24480,30470,30498,30769,31758,30217,33456,34318,34319,38638,36116,29863,26213,29866,26418,25726,25785,40206,31157,35926,26433,30674,32111,30753,32711,37118,37713,38164,25443,40209,35065,36785,30080,36793,32399,36757,32411,36674,32419,30721,37975,36901,38021,40109,39779,25768,26130,35868,36541,37125,35658,37305,36822,36945,34674,33437,35790,33175,40179,34314,34897,30256,30288,30212'
$arrSeries = $lstSeries -Split ","

# Initialize the Report File
$curDte = Get-Date -Format 'yyyyMMdd_HHmmss'
New-Item -Path "Subscriptions$($curDte).csv" -ItemType "File" -Value "Series,LP ID,Org Id,Sub ID" -Force

# Connect to LOD.Core
Connect-LabOnDemand -ERRORAction 'Continue'

$x = 1
foreach ($ls in $arrSeries) {
	$y = 1
	write-output "Series $($x) / $($arrSeries.Count)"
	$lps = Search-LODLabProfile -LabseriesId $ls
    foreach ($lp in $lps) {
		write-output "  Profile $($y) / $($lps.count)"
        $lab = Get-LODLabProfile -ID $lp.ID
	    Add-Content -Path "Subscriptions$($curDte).csv" -Value "$($lab.SeriesId),$($lab.Id),$($lab.OrganizationId),$($lab.CloudSubscriptionPoolId)"
		$y++
    }
	$x++
}