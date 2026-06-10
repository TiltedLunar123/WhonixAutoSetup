#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

BeforeAll {
    $libPath = Join-Path (Split-Path $PSScriptRoot -Parent) "lib/allocation.ps1"
    . $libPath
}

Describe "Get-VmResourceAllocation" {
    Context "Gateway is always fixed" {
        It "gives the Gateway 1 core and 1024 MB regardless of host size" {
            foreach ($gb in 8, 16, 32, 64) {
                $a = Get-VmResourceAllocation -TotalRamBytes ([long]($gb * 1GB)) -CpuCores 8
                $a.GatewayCores | Should -Be 1
                $a.GatewayRamMB | Should -Be 1024
            }
        }
    }

    Context "RAM tier selection" {
        It "uses the 25% slice below 16 GB (8 GB host)" {
            # available = 8192 - 5120 = 3072; 25% = 768, floored up to the 2048 minimum
            $a = Get-VmResourceAllocation -TotalRamBytes ([long](8 * 1GB)) -CpuCores 4
            $a.WorkstationRamMB | Should -Be 2048
        }

        It "uses the 33% slice from 16 up to 32 GB (16 GB host)" {
            # available = 16384 - 5120 = 11264; 33% = 3717.12 -> 3717 -> 128-step -> 3712
            $a = Get-VmResourceAllocation -TotalRamBytes ([long](16 * 1GB)) -CpuCores 8
            $a.WorkstationRamMB | Should -Be 3712
        }

        It "uses the 40% slice at 32 GB and up (32 GB host)" {
            # available = 32768 - 5120 = 27648; 40% = 11059.2 -> 11059 -> 11008, then capped to 8192
            $a = Get-VmResourceAllocation -TotalRamBytes ([long](32 * 1GB)) -CpuCores 16
            $a.WorkstationRamMB | Should -Be 8192
        }
    }

    Context "Workstation RAM floor and ceiling" {
        It "never drops the Workstation below 2048 MB" {
            $a = Get-VmResourceAllocation -TotalRamBytes ([long](8 * 1GB)) -CpuCores 4
            $a.WorkstationRamMB | Should -BeGreaterOrEqual 2048
        }

        It "never gives the Workstation more than 8192 MB" {
            $a = Get-VmResourceAllocation -TotalRamBytes ([long](128 * 1GB)) -CpuCores 32
            $a.WorkstationRamMB | Should -Be 8192
        }
    }

    Context "Workstation RAM is rounded down to a 128 MB step" {
        It "lands on a 128 MB boundary (16 GB host -> 3712)" {
            $a = Get-VmResourceAllocation -TotalRamBytes ([long](16 * 1GB)) -CpuCores 8
            ($a.WorkstationRamMB % 128) | Should -Be 0
            $a.WorkstationRamMB | Should -Be 3712
        }
    }

    Context "CPU core allocation" {
        It "caps the Workstation at 2 cores below 16 GB" {
            $a = Get-VmResourceAllocation -TotalRamBytes ([long](8 * 1GB)) -CpuCores 16
            $a.WorkstationCores | Should -Be 2
        }

        It "caps the Workstation at 3 cores in the 16 to 32 GB tier" {
            $a = Get-VmResourceAllocation -TotalRamBytes ([long](16 * 1GB)) -CpuCores 16
            $a.WorkstationCores | Should -Be 3
        }

        It "caps the Workstation at 4 cores at 32 GB and up" {
            $a = Get-VmResourceAllocation -TotalRamBytes ([long](64 * 1GB)) -CpuCores 32
            $a.WorkstationCores | Should -Be 4
        }

        It "leaves a core for the host, so a 4-core 16 GB host gives the Workstation 2" {
            # availableCores = 4 - gateway(1) - host(1) = 2, capped by the tier at 3
            $a = Get-VmResourceAllocation -TotalRamBytes ([long](16 * 1GB)) -CpuCores 4
            $a.WorkstationCores | Should -Be 2
        }

        It "still hands out at least 1 core on a 2-core host" {
            # availableCores would be 0 here; the floor pulls it back to 1
            $a = Get-VmResourceAllocation -TotalRamBytes ([long](16 * 1GB)) -CpuCores 2
            $a.WorkstationCores | Should -Be 1
        }
    }
}
