$Bedrift = "StAn"

$DomainController = Read-Host "Domenekontrollers adresse. '.' er lokal maskin."
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

.PARAMETER Engangspassord

Ett engangspassord for brukeren.
Dette må endres av brukeren etter første innlogging.

.PARAMETER Avdeling

Avdelingen brukeren tilhører.
Dette gir hvilken OU Brukeren opprettes i.
Aksepterte verdier må endres i skriptet.
Dersom ikke oppgitt, blir brukeren lagt i avdelingen Produksjon.

.PARAMETER HjemmemappeDrev

Hvilket drev brukerens hjemmemappe skal monteres til.
Standard 'Z'.

.PARAMETER HjemmemappeRot

Nettverksaddressen til mappen hjemmemappen skal opprettes i.
Brukerens hjemmemappe vil ligge i denne mappen, og ha navn tilsvarende brukerens SAMAccountName.

.PARAMETER IkkeLeggIGruppe

Dersom brukeren ikke skal legges til standardgruppen for avdelingen, benytt denne.

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
            HelpMessage = "Engangspassord for brukeren. Dette endres av brukeren etter første innlogging."
        )]
        [securestring]
        $Engangspassord = (Read-Host "Engangspassord" -AsSecureString),
        [Parameter(
            Position = 3
        )]
        [ValidateSet("Administrasjon", "Produksjon", "Salg", "Utvikling")]                    
        [string]
        $Avdeling = "Produksjon",
        [Parameter(
            Position = 4,
            HelpMessage = "Drevet brukerens hjemmemappe skal settes til. Standard 'Z'."
        )]
        [string]
        $HjemmemappeDrev = "Z", 
        [Parameter(
            Position = 5,
            HelpMessage = "Adresse til hvor brukerens hjemmemappe skal opprettes. Standard C:\Share\Hjemmemappper."
        )]
        [string]
        $HjemmemappeRot = "\\Solem-ad\Share\Hjemmemapper",
        [switch]
        $IkkeLeggIGruppe
    )
    $Brukernavn = New-Brukernavn $Fornavn $Etternavn
    $FulltNavn = "{0} {1}" -f $Fornavn, $Etternavn
    $UPN = New-UPN $Fornavn $Etternavn
    if (-not ($HjemmemappeRot.EndsWith('\') -or $HjemmemappeRot.EndsWith('/'))) {
        $HjemmemappeRot = "{0}\" -f $HjemmemappeRot
    }
    $Hjemmemappe = "{0}{1}" -f $HjemmemappeRot, $Brukernavn

    $Domene = Invoke-Command -Session $Session -ScriptBlock {
        Get-ADDomain
    } -ErrorVariable err
    $AvdelingOUPath = "OU={0},OU={1},{2}" -f $Avdeling, $Bedrift, ($Domene.DistinguishedName)
    try {
        $err = Invoke-Command -Session $Session -ScriptBlock {
            New-ADUser `
                -Name using:$FulltNavn `
                -DisplayName using:$FulltNavn `
                -GivenName using:$Fornavn `
                -Surname using:$Etternavn `
                -UserPrincipalName using:$UPN `
                -SamAccountName using:$Brukernavn `
                -AccountPassword using:$Engangspassord `
                -Enabled using:$true `
                -ChangePasswordAtLogon using:$true `
                -Path using:$AvdelingOUPath `
                -Department using:$Avdeling `
                -Company using:$Bedrift `
                -HomeDirectory using:$Hjemmemappe `
                -HomeDrive using:$HjemmemappeDrev `
                -ErrorVariable err
            return $err
        }
        # Kaster en tom feilmelding for å entre catch-blokka. Innholdet i selve feilmeldingen blir ikke utnyttet.
        if ($err.Count -gt 0) {
            Throw "" 
        }
        Write-Host ("Brukeren {0} ble opprettet for {1}." -f $Brukernavn, $FulltNavn) -ForegroundColor Green

        If ( -not $IkkeLeggIGruppe) {
            $err = Invoke-Command -Session $Session -ScriptBlock {
                Add-ADGroupMember $Avdeling $UPN -ErrorVariable err
                return $err
            }
            # Kaster en tom feilmelding for å entre catch-blokka. Innholdet i selve feilmeldingen blir ikke utnyttet.
            if ($err.Count -gt 0) {
                Throw "" 
            }
            Write-Host ("Brukeren {0} ble medlem av gruppen {1}." -f $Brukernavn, $Avdeling) -ForegroundColor Green
        }
    }
    catch {
        Write-Host ("Opprettelse av bruker {0} for {1} feilet. Se feilmelding under." -f $Brukernavn, $FulltNavn) -ForegroundColor Yellow
        Write-Host $err.Exeption.Message
    }
}

<#
.SYNOPSIS

Oppretter flere brukere fra CSV-fil.
Behøver feltene Fornavn, Etternavn, Avdeling, Engangspassord

.PARAMETER Path

Sti til CSV-fil. Dersom ikke oppgitt, vil en filutforsker dukke opp.
#>
function New-CustomADBrukerFromCSV {
    Param (
        [Parameter(
            Position = 0
        )]
        [string]
        # Sti til CSV-Fil
        $Path = "",
        [char]
        # Separasjonstegn i CSV. Standard ';'.
        $Delimiter = ';'
    )

    # Dersom brukeren ikke oppgir en sti til en CSV-fil, åpne dialogboks.
    If ($Path.Length -le 0) {
        do {
            $CsvFil = New-Object System.Windows.Forms.OpenFileDialog
            $CsvFil.Filter = 
            "csv files (*.csv)|*.csv|txt files (*.txt)|" +
            "*.txt|All files (*.*)|*.*"
            $CsvFil.Title = "Åpne opp CSV fil som inneholder brukere"
            $CsvFil.ShowDialog()
        } until ($CsvFil.FileName -ne "")
        $Path = $CsvFil.FileName
    }

    $Brukere = Import-Csv $CsvFil.FileName -Delimiter ";"
    
    foreach ($Bruker in $Brukere) {
		
        # Hent verdier fra CSV-fil og opprett bruker
        $Passord = ConvertTo-SecureString $Bruker.Passord -AsPlainText -Force 
        $Etternavn = $Bruker.Etternavn.Trim() 
        $Fornavn = $Bruker.Fornavn.Trim()
        $Avdeling = $Bruker.Avdeling.Trim()
        
        New-CustomADBruker $Fornavn $Etternavn $Avdeling $Passord
    }
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
    Invoke-Command -Session $Session -ScriptBlock {
        Get-ADUser -Identity $GrunnBrukernavn
    } -ErrorVariable err -ErrorAction SilentlyContinue
    $i = 1
    #Dersom brukernavnet er i bruk, vil $err.Count være lik 0. Legger til $i, som er monotonisk voksende,
    #til et ledig brukernavn er funnet
    while ($err.Count -eq 0) {
        $Brukernavn = "{0}{1}" -f $GrunnBrukernavn, ($i++)
        Invoke-Command -Session $Session -ScriptBlock {
            Get-ADUser -Identity using:$Brukernavn
        } -ErrorVariable err -ErrorAction SilentlyContinue
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
    $Fornavn = Format-NorwegianChars ($Fornavn.Trim().Replace(' ', '.'))
    $Etternavn = Format-NorwegianChars ($Etternavn.Trim().Replace(' ', '.'))
    $Bruker = "{0}.{1}" -f $Fornavn, $Etternavn
    $Domene = Invoke-Command -Session $Session -ScriptBlock {
        "@{0}" -f (Get-ADDomain).Forest
    } -ErrorVariable err -ErrorAction SilentlyContinue
        
    $GrunnUPN = "{0}{1}" -f $Bruker, $Domene
    $UPN = $GrunnUPN
    #Kontrollerer om UPN er i bruk
    Invoke-Command -Session $Session -ScriptBlock {
        Get-ADUser -Filter {UserPrincipalName -like using:$GrunnUPN} -ErrorVariable err
    } -ErrorVariable err -ErrorAction SilentlyContinue
    $i = 1
    #Dersom UPN er i bruk, vil $err.Count være lik 0. Legger til $i, som er monotonisk voksende,
    #til en ledig UPN er funnet
    while ($err.Count -eq 0) {
        $UPN = "{0}{1}" -f $GrunnUPN, ($i++)
        $Domene = Invoke-Command -Session $Session -ScriptBlock {
            Get-ADUser  -Filter {UserPrincipalName -like using:$UPN}
        } -ErrorVariable err
    }
    return $UPN
}

<#
.SYNOPSIS

Bytter ut tegnene ÆØÅæøå med EOAeoa.
#>
function Format-NorwegianChars {
    Param (
        [Parameter(
            Mandatory = $true,
            Position = 0
        )]
        [string]
        #Streng som skal normaliseres.
        $OriginalString
    )
    $FormatertString = $OriginalString.Replace('Æ', 'E').Replace('æ', 'e').Replace('Ø', 'O').Replace('ø', 'o').Replace('Å', 'A').Replace('å', 'a')
    return $FormatertString

}

Function Remove-CustomADUser {
    Param(
        [Parameter(
            Mandatory = $true,
            Position = 0
        )]
        [string]
        $Identity
    )
    $User = Invoke-Command -Session $Session -ScriptBlock {
        Get-ADUser -Identity using:$Identity -Properties HomeDirectory
    } -ErrorVariable err -ErrorAction SilentlyContinue

    if ($err.Count -gt 0) {
        Write-Warning "Bruker ikke funnet"
        return
    }

    Invoke-Command -Session $Session -ScriptBlock {
        Remove-ADUser $Identity
    } -ErrorVariable err -ErrorAction SilentlyContinue
    if ($user.HomeDirectory.Count -gt 0) {
        Remove-Item $user.HomeDirectory -Recurse -Force
    }
}