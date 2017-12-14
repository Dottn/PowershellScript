$Bedrift = "PSEksamenBedrift"

$DomainController = Read-Host "Domenekontrollers adresse"
$Credential = Get-Credential -Message "Logg inn med brukeradministrasjonsrettigheter"

$Session = New-PSSession $DomainController -Credential $Credential


<#
.SYNOPSIS

Oppretter en ny ADBruker i tilkoblet domene, med SAMAccountName, UPN og hjemmemappe.

.DESCRIPTION

Oppretter en ny ADBruker i tilkoblet domene, med SAMAccountName, UPN og hjemmemappe. 
Brukeren blir lagt i OU=$Avdeling,OU=$Bedrift,$Domene.DistinguishedName(). 
Brukerens SAMAccountName og UPN blir generert på bakgrunn av $Fornavn og $Etternavn.

.PARAMETER Fornavn

Brukerens fulle fornavn.
Brukes til å generere SAMAccountName og UPN.
2-64 tegn.

.PARAMETER Etternavn

Brukerens fulle etternavn.
Brukes til å generere SAMAccountName og UPN.
2-64 tegn.

.PARAMETER Avdeling

Avdelingen brukeren tilhører.
Dette gir hvilken OU Brukeren opprettes i.
2-64 tegn.

.PARAMETER Engangspassord

Ett engangspassord for brukeren.
Dette må endres av brukeren etter første innlogging.

.PARAMETER HjemmemappeDrev

Hvilket drev brukerens hjemmemappe skal monteres til.
Standard 'Z'.

.PARAMETER HjemmemappeRot

Nettverksaddressen til mappen hjemmemappen skal opprettes i.
Brukerens hjemmemappe vil ligge i denne mappen, og ha navn tilsvarende brukerens SAMAccountName.

.EXAMPLE

\\TODO

.NOTES

$Bedrift og tilkoblet domene settes under import av modulen.
#>
function New-CustomADBruker {
    Param(
        [Parameter(
            Mandatory = $true,
            Position = 0,
            HelpMessage = "Brukerens fulle fornavn. 2-64 tegn."
        )]
        [ValidateLength(2, 64)]
        [string]
        $Fornavn = (Read-Host "Fornavn"),        
        [Parameter(
            Mandatory = $true,
            Position = 1,
            HelpMessage = "Brukerens fulle etternavn. 2-64 tegn."
        )]
        [ValidateLength(2, 64)]                    
        [string]
        $Etternavn = (Read-Host "Etternavn"),
        [Parameter(
            Mandatory = $true,
            Position = 2,
            HelpMessage = "Avdelingen brukeren tilhører. 2-64 tegn."
        )]
        [ValidateLength(2, 64)]                    
        [string]
        $Avdeling = (Read-Host "Avdeling"),
        [Parameter(
            Mandatory = $true,
            Position = 3,
            HelpMessage = "Engangspassord for brukeren. Dette endres av brukeren etter første innlogging."
        )]
        [securestring]
        $Engangspassord = (Read-Host "Engangspassord" -AsSecureString),
        [Parameter(
            Position = 4,
            HelpMessage = "Drevet brukerens hjemmemappe skal settes til. Standard 'Z'."
        )]
        [string]
        $HjemmemappeDrev = "Z", [Parameter(
            Position = 5,
            HelpMessage = "Adresse til hvor brukerens hjemmemappe skal opprettes. Standard C:\Share\Hjemmemappper."
        )]
        [string]
        $HjemmemappeRot = "C:\Share\Hjemmemappper"
    )
    $Brukernavn = New-Brukernavn $Fornavn $Etternavn
    $FulltNavn = "{0} {1}" -f $Fornavn, $Etternavn
    $UPN = New-UPN $Fornavn $Etternavn
    if (-not ($HjemmemappeRot.EndsWith('\') -or $HjemmemappeRot.EndsWith('/'))) {
        $HjemmemappeRot = "{0}\" -f $HjemmemappeRot
    }
    $Hjemmemappe = "{0}{1}" -f $HjemmemappeRot, $Brukernavn

    $Domene = Invoke-Command -Session $Session -ScriptBlock {
        "@{0}" -f (Get-ADDomain)
    } -ErrorVariable err
    $AvdelingOUPath = "OU={0},OU={1},{2}" -f $Avdeling, $Bedrift, $Domene.DistinguishedName

    New-ADUser `
        -DisplayName $FulltNavn `
        -GivenName $Fornavn `
        -Surname $Etternavn `
        -UserPrincipalName $UPN `
        -SamAccountName $Brukernavn `
        -AccountPassword $Engangspassord `
        -Enabled $true `
        -ChangePasswordAtLogon $true `
        -Path $AvdelingOUPath `
        -Department $Avdeling `
        -Company $Bedrift `
        -HomeDirectory $Hjemmemappe `
        -HomeDrive $HjemmemappeDrev
}

<#
.SYNOPSIS

Oppretter brukernavn basert på $Fornavn og $Etternavn

.DESCRIPTION

Oppretter brukernavn basert på $Fornavn og $Etternavn.
Brukernavnet er de to til tre første tegnene fra $Fornavn og $Etternavn satt sammen til et brukernavn på 4-6 tegn.
Det blir kun brukt to tegn dersom navnet kun inneholder to tegn.

.EXAMPLE

C:\PS:> New-Brukernavn Sivert Solem
sivsol

.EXAMPLE

C:\PS:> New-Brukernavn Asbjørn Da
asbda

.NOTES
General notes
#>
Function New-Brukernavn {
    Param(
        [Parameter(
            Mandatory = $true,
            Position = 0
        )]
        [ValidateLength(2, 64)]
        [string]
        #Brukerens fulle fornavn.
        $Fornavn = (Read-Host "Fornavn"),        
        [Parameter(
            Mandatory = $true,
            Position = 1
        )]
        [ValidateLength(2, 64)]            
        [string]
        #Brukerens fulle etternavn.
        $Etternavn = (Read-Host "Etternavn")
    )
    $Fornavn = Format-NorwegianChars $Fornavn.Trim().ToLower()
    $Etternavn = Format-NorwegianChars $Etternavn.Trim().ToLower()
    if ($Fornavn.Length -gt 2) {
        $Fornavn = $Fornavn.Substring(0, 3)
    }
    if ($Etternavn.Length -gt 2) {
        $Etternavn = $Etternavn.Substring(0, 3)
    }
    $GrunnBrukernavn = "{0}{1}" -f $Fornavn, $Etternavn
    $Brukernavn = $GrunnBrukernavn
    #Kontrollerer om brukernavnet er i bruk
    Get-ADUser -Identity $GrunnBrukernavn -ErrorVariable err
    $i = 1
    #Dersom brukernavnet er i bruk, vil $err.Count være lik 0. Legger til $i, som er monotonisk voksende,
    #til et ledig brukernavn er funnet
    while ($err.Count -eq 0) {
        $Brukernavn = "{0}{1}" -f $GrunnBrukernavn, ($i++)
        Invoke-Command -Session $Session -ScriptBlock {
            Get-ADUser -Identity $Brukernavn
        } -ErrorVariable err
    }
    return $Brukernavn
}

<#
.SYNOPSIS

Oppretter UPN basert på $Fornavn og $Etternavn på formen $Fornavn.$Etternavn@domene.tld

.DESCRIPTION

Oppretter UPN basert på $Fornavn og $Etternavn

Tar bort mellomrom fra start og slutt av $Fornavn og $Etternavn.
Dersom $Fornavn eller $Etternavn inneholder mellomrom, ' ', blir disse byttet ut med punktum, '.'.
Henter domenenavn fra tilkoblet AD.

.EXAMPLE

An example

.NOTES

General notes
#>
function New-UPN {
    Param(
        [Parameter(
            Mandatory = $true,
            Position = 0
        )]
        [ValidateLength(2, 64)]
        [string]
        #Brukerens fulle fornavn.
        $Fornavn = (Read-Host "Fornavn"),
        [Parameter(
            Mandatory = $true,
            Position = 1
        )]
        [ValidateLength(2, 64)]            
        [string]
        #Brukerens fulle etternavn.
        $Etternavn = (Read-Host "Etternavn")
    )
    $Fornavn = Format-NorwegianChars $Fornavn.Trim().Replace(' ', '.')
    $Etternavn = Format-NorwegianChars $Etternavn.Trim().Replace(' ', '.')
    $Bruker = "{0}.{1}" -f $Fornavn, $Etternavn
    $Domene = Invoke-Command -Session $Session -ScriptBlock {
        "@{0}" -f (Get-ADDomain).Forest
    } -ErrorVariable err
        
    $GrunnUPN = "{0}{1}" -f $Bruker, $Domene
    $UPN = $GrunnUPN
    #Kontrollerer om UPN er i bruk
    Invoke-Command -Session $Session -ScriptBlock {
        Get-ADUser -Filter {UserPrincipalName -like $GrunnUPN} -ErrorVariable err
    } -ErrorVariable err
    $i = 1
    #Dersom UPN er i bruk, vil $err.Count være lik 0. Legger til $i, som er monotonisk voksende,
    #til en ledig UPN er funnet
    while ($err.Count -eq 0) {
        $UPN = "{0}{1}" -f $GrunnUPN, ($i++)
        $Domene = Invoke-Command -Session $Session -ScriptBlock {
            Get-ADUser  -Filter {UserPrincipalName -like $UPN}
        } -ErrorVariable err
    }
    return $UPN
}

<#
.SYNOPSIS

Bytter ut tegnene ÆØÅæøå med EOAeoa.
#>
function Private:Format-NorwegianChars {
    Param (
        [Parameter(
            Mandatory = $true,
            Position = 0
        )]
        [string]
        #Streng som skal normaliseres.
        $OriginalString
    )
    $OriginalString.ToLower()
    $FormatertString = $OrigialString.Replace('Æ', 'E').Replace('æ', 'e').Replace('Ø', 'O').Replace('ø', 'o').Replace('Å', 'A').Replace('å', 'a')
    return $FormatertString

}

Function test-session {
    $Session
}