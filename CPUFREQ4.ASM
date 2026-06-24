;-------------------------------------------------------------------------------
;Program    : CPUFreq
;Version    : 4
;Author     : Cleber Jean Barranco <cleberjean@hotmail.com>
;Date       : 24jun2026
;License    : MIT (See LICENSE file)
;
;Description: Show current CPU frequency in DOS by reading the
;             CPU clock through of APERF (0xE8) MSR or TSC register
;             and show as "#.## GHz".
;
;To Compile : "nasm cpufreq.asm -o cpufreq.com" or
;             "fasm cpufreq.asm cpufreq.com"
;
;NOTE ABOUT OF FASM USE: It may generate 80386 conditional jumps, that can
;                        turn the binary file incompatible with 16 bits
;                        processors (8086/8088, 80186 and 80286), causing
;                        crashing on the execution. See the solution on
;                        Bad_Proc_Near_Jump label below.
;
;-------------------------------------------------------------------------------


;-------------------------------------------------------------------------------
; History:
; --------
;
;     10may2026
;         + Changed Real Mode checking by the use of SMSW instruction
;           (MOV EAX,CR0 NOT WORKS in Windows 3.1 in Enhanced Mode).
;         + Created the Bad_Proc_Near_Jump label, after 286 checking routine,
;           to fix the ausence of a near conditional instruction on 16 bits
;           processors.
;
;     21jun2026
;         - Removed Priviligied Mode checking (RDTSC is working with
;           EMM386.EXE loaded or Windows in Enhanced Mode).
;
;     22jun2026
;         + Reintroduced test for Windows Enhanced Mode (RDMSR instructions
;           trigger a GPF in WIndows Enhanced Mode)
;         + Changed timing routine (Wait_1_Second_Change) to use clock ticks 
;           Wait_Clock_Tick_Change and Pause_1_Clock_Tick for the pause to 
;           get the processor frequency (faster).
;
;     23jun2026
;         * Removed CLOCKS_LSDW, CLOCKS_MSDW and replaced by PUSH EAX,
;           PUSH EDX, POP ECX and POP EBX. Saving 8 bytes.
;         + Changed Wait_Clock_Tick_Change and Pause_1_Clock_Tick for
;           Detect_Clock_Tick for both functions, saving 16 bytes.
;         + Other more optimizations.
;
;     24jun2026
;         + Improved frequency calculation accuracy by to multiply the clocks
;           read by TSC or IA32_APERF, by 10 and after to divide by 549254.
;         * Changed the Detect_Clock_Tick routine name for
;           Wait_Clock_Tick_Change for better clarity.
;-------------------------------------------------------------------------------


;-------------------------------------------------------------------------------
; Constants    
;-------------------------------------------------------------------------------
    APERF_MSR_FLAG      equ 1
    IA32_APERF_MSR      equ 0xE8
    TSC_REG_FLAG        equ 00010000b
    INVARIANT_TSC_FLAG  equ 1


;-------------------------------------------------------------------------------
; Directive for .COM file    
;-------------------------------------------------------------------------------
    org    100h                    ; Program is a DOS .COM file


;-------------------------------------------------------------------------------
; Directive for Code Type
;-------------------------------------------------------------------------------
    cpu    8086                    ; To use 8086 code below (Nasm directive)


;-------------------------------------------------------------------------------
; Get DOS Version and Store for Support Checking of INT 21h 0x4C Function
;-------------------------------------------------------------------------------
    mov    ax,3000h
    int    21h                     ; Get DOS version
    mov    [DOS_VERSION],al        ; and store for checkings


;-------------------------------------------------------------------------------
; Processor Detection
; Double check for 8086/8088.
; Taken from Intel Pentium Processor User's Manual, Volume 3, 
; Chapter 5.3 - SAMPLE CPUID IDENTIFICATION/FPU DETECTION CODE,
; pages 129 to 123, from 1993.
; Example 5-1. CPU Identification and FPU Detection.
; The original commentary says:
;       "This program has been developed by Intel Corporation. You have
;        Intel's permission to incorporate this source code into your
;        product royalty free."
;
; Author Note: Only CX register was changed to BX.
;
; Processors later of 8086 always push SP to stack, and then decrement SP 
; by 2. 8086 always decrement SP by 2 and then push it on stack.
; Also bits 12..15 are always set on the 8086 processor.
; [MODIFIED] Test only bits 14 and 15, due a detection fail when in
;            Priviligied Level != 0.
;-------------------------------------------------------------------------------
Test_8086:
    push   sp                      ; Push SP
    pop    ax                      ; And restore in AX
    sub    ax,sp                   ; Will clear AX if CPU is an 80286 or later
    jnz    Bad_Proc_Near_Jump      ; Processor is an 80186 or early
    pushf
    pop    bx                      ; Save FLAGS in BX
    mov    ax,bx                   ; Copy flags to AX
    and    ax,0FFFh                ; Clear bits 12..15
    push   ax
    popf                           ; Clear bits 12..15 in FLAGS
    pushf
    pop    ax                      ; Copy flags again to AX
;    and    ax,0F000h               ; Check if bits 12..15 still always clean
;    jnz    Bad_Proc                ; Bits 12..15 from Flags Register remain set (processor is an 8086/80186)
    and    ax,0C000h               ; Check if bits 14 and 15 still always clean
    jnz    Bad_Proc_Near_Jump      ; Bits 14 and 15 from Flags Register remain set (processor is an 8086/80186)


;-------------------------------------------------------------------------------
; Intel 286 CPU Checking
; Bits 12-15 are always clear on the Intel 286 processor.
;-------------------------------------------------------------------------------
Test_80286:
    mov    ax,bx                   ; Copy flags to AX
    or     ax,0F000h               ; Set bits 12..15
    push   ax
    popf
    pushf
    pop    ax
    and    ax,0F000h               ; If bits 12..15 are cleared, then CPU=80286
    jnz    Test_80386              ; Processor is an 80386
         
         
;-------------------------------------------------------------------------------
; Conditional Near Jump Fix for the 16 bits Processors
; Processors 8086/8088, 80186 and 80286 has Conditional Short Jumps Only.
;-------------------------------------------------------------------------------
Bad_Proc_Near_Jump:           
    jmp    Bad_Proc

           
           ;+----------------------------------------------------+;
           ;| Starting here, is safe to use 32 bits instructions |;
           ;+----------------------------------------------------+;

;-------------------------------------------------------------------------------
; Directive for Code Type
;-------------------------------------------------------------------------------
    cpu    386                     ; To use 80386 code below (Nasm directive)
    

;-------------------------------------------------------------------------------
; Intel386 CPU Checking
; The AC bit, bit #18, is a new bit introduced in the EFLAGS
; register on the Intel486 DX CPU to generate alignment faults.
; This bit can not be set on the Intel386 CPU.
;-------------------------------------------------------------------------------
Test_80386:
    push   bx
    popf                           ; Restore original FLAGS
    pushfd
    pop    ebx                     ; Save original EFLAGS in EBX
    mov    eax,ebx                 ; Copy original EFLAGS to EAX
    xor    eax,40000h              ; Flip AC bit in EFLAGS
    push   eax
    popfd
    pushfd
    pop    eax                     ; Get new EFLAGS value
    xor    eax,ebx                 ; Compare original EFLAGS with new EFLAGS. Can't
                                   ; toggle AC bit, CPU=80386
    jz     Bad_Proc

Test_80486:
    mov    eax,ebx                 ; Copy original EFLAGS to EAX
    xor    eax,200000h             ; Flip ID bit in EFLAGS
    push   eax
    popfd
    pushfd
    pop    eax                     ; Get new EFLAGS value
    xor    eax,ebx                 ; Compare original EFLAGS with new EFFAGS
    jz     Bad_Proc                ; If ID bit cannot be changed, CPU=80486
                                   ; without CPUID instruction functionality

;-------------------------------------------------------------------------------
; For safety only, restore original EFLAGS (not is on original source code)
;-------------------------------------------------------------------------------
    push   ebx
    popfd


;-------------------------------------------------------------------------------
; Now is safe to use the CPUID instruction to get processor informations
;-------------------------------------------------------------------------------
    cpu    586                     ; To use Pentium code below (Nasm directive)

    xor    eax,eax                 ; EAX = 0
    cpuid
    cmp    al,1                    ; Check # of leaves supported by CPUID
    jb     Bad_Proc


;------------------------------------------------------------------------------
; Checks if Windows is in Enhanced Mode
; Windows in Enhanced Mode not allow execute the RDMSR instruction
; Exits with error code 3 if Windows in Enhanced Mode
; With EMM386.EXE and DOS only is OK.
;------------------------------------------------------------------------------
    mov    ax,160Ah                ; Get Windows version and mode
    int    2Fh
    test   ax,ax                   ; Checks if function is supported
    jnz    Check_TSC_APERF_MSR     ; Function not supported or not in Windows
    cmp    cl,2                    ; Checks Windows Standard Mode
    je     Check_TSC_APERF_MSR     ; Ok. Windows in Standard Mode
    mov    dx,WINDOWS_E_MODE_MSG   ; Windows in Enhanced Mode error message
    mov    ah,09h
    int    21h
    mov    ax,4C03h                ; Exit with error code 3
    int    21h


;-------------------------------------------------------------------------------
; Check for Time Stamp Counter Register and APERF MSR   
;-------------------------------------------------------------------------------
Check_TSC_APERF_MSR:
    push   bx                      ; Save cpuid maximum leaves
;    mov    eax,1
    xor    eax,eax
    inc    ax                      ; EAX = 1 (2 bytes smaller than MOV EAX,1)
    cpuid
    test   dl,TSC_REG_FLAG         ; Test if processor has a TSC register (EDX bit 4 = 1 = TSC Register OK)
    pop    ax                      ; Restore cpuid maximum leaves in AL
                                   ; (allow to use the CMP AL,06 instruction
                                   ;  that is one byte smaller then CMP BL,6
                                   ;  if to use POP BX).
    jz     Bad_Proc                ; Skip if processor not has a TSC register
    cmp    al,06h                  ; CPUID leaves number is 6 or greater?
    jb     Check_Invariant_TSC     ; No, then skip APERF checking (processor not support IA32_APERF MSR)
    

;-------------------------------------------------------------------------------
; Check for IA32_APERF MSR    
;-------------------------------------------------------------------------------
;    mov    eax,06h
    xor    eax,eax
    mov    al,06h                  ; EAX = 6 (1 byte smaller than MOV EAX,6)
    cpuid
    and    cl,APERF_MSR_FLAG       ; Check if processor has APERF MSR (CL = 1 if yes)
    mov    [CPU_HAS_APERF],cl      ; Set APERF flag de acordo com o valor do cpuid flag
    jz     Check_Invariant_TSC     ; Processor not has APERF. Let's go to use TSC
    mov    dx,APERF_READING_MSG
    mov    ah,09h
    int    21h                     ; Show "Reading the CPU frequency through of IA32_APERF MSR..." message
    jmp    Get_CPU_Frequency


;-------------------------------------------------------------------------------
; Check if the Processor has an Invariant Time Stamp Counter
; Test only if CPUID supports 80000007h Extended Leaf
;-------------------------------------------------------------------------------
Check_Invariant_TSC:    
    mov    eax,80000000h           ; Check if CPUID has Extended Leaves
    cpuid
    cmp    eax,80000007h           ; CPUID has 80000007h Extended Leaf?
    jb     Show_TSC_Reading_Msg    ; No, then skip Invariant TSC checking
    mov    eax, 0x80000007         ; Check Invariant TSC presence
    cpuid
    test   dh,INVARIANT_TSC_FLAG   ; Check if processor has an Invariant TSC (EDX Bit 8 = 1 = Invariant TSC present)
    jz     Show_TSC_Reading_Msg    ; No, then skip Invariant TSC message
    mov    dx,INVARIANT_TSC_MSG
    mov    ah,09h
    int    21h                     ; Show "Processor has an Invariant TSC!" Message

Show_TSC_Reading_Msg:
    mov    dx,TSC_READING_MSG
    mov    ah,09h
    int    21h                     ; Show "Reading the CPU frequency through of TSC register..." message


Get_CPU_Frequency:    
    call   Wait_Clock_Tick_Change  ; Timing start
    test   byte [CPU_HAS_APERF],1
    jz     Get_Initial_TSC_Value   ; Processor has not IA32_APERF
;    xor    eax,eax                ; Not need (according to ChatGPT)
    cpuid                          ; To serialize instructions (MANDATORY!)
    xor    ecx,ecx
    mov    cl,IA32_APERF_MSR       ; Load ECX with IA32_APERF (0xE8) MSR
    rdmsr
    jmp    Save_Initial_Value


Get_Initial_TSC_Value:    
    xor    eax,eax                 ; Double function, add equalization clocks
                                   ; and clear eax for CPUID instruction
    cpuid                          ; To serialize instructions (MANDATORY!)
    rdtsc
    

;-------------------------------------------------------------------------------
; Saves Initial Clocks Counting Got from TSC or IA32_APERF MSR Value
;-------------------------------------------------------------------------------
Save_Initial_Value:    
    push   eax                     ; 23jun2026
    push   edx                     ; 23jun2026


;-------------------------------------------------------------------------------
; 1 Clock Tick Pause (54,9254 ms)
; Waits clock tick to change
;-------------------------------------------------------------------------------
    call   Wait_Clock_Tick_Change

;-------------------------------------------------------------------------------
; Read IA32_APERF MSR or TSC after 1 Clock Tick and Get # of Elapsed Clocks
;-------------------------------------------------------------------------------
    test   byte [CPU_HAS_APERF],1
    jz     Get_Final_TSC_Value
;    xor    eax,eax                ; Not need (according to ChatGPT)
    cpuid                          ; To serialize instructions (MANDATORY!)
    xor    ecx,ecx
    mov    cl,IA32_APERF_MSR       ; Load ECX with IA32_APERF (0xE8) MSR
    rdmsr
    jmp    Calculate_CPU_Frequency


Get_Final_TSC_Value:    
    xor    eax,eax                 ; Double function, add equalization clocks
                                   ; and clear eax for CPUID instruction
    cpuid                          ; To serialize instructions (MANDATORY!)
    rdtsc


;-------------------------------------------------------------------------------
; Subtracts Initial Clocks Counting Got from Actual Clocks Counts
; from TSC or IA32_APERF MSR Value
;-------------------------------------------------------------------------------
Calculate_CPU_Frequency:    
    pop    ecx
    pop    ebx
    sub    eax,ebx
    sbb    edx,ecx

    mul    eax,10                  ; Multiply clocks number by 10 to divide 
                                   ; by 1/10 of a clock tick (for better 
                                   ; resolution)
    mov    ecx,549254              ; 1.000.000.000 / 1,820651 (clock ticks
                                   ; in 1 second / 10) (clock tick = timing 
                                   ; window)
                                   ; Divide it like this to get the frequency
                                   ; with 4 numbers (1 integer and 3 decimal 
                                   ; places for rounding purpose).
    div    ecx                     ; Get frequency in format #### (#.### with 
                                   ; a dot before of three last numbers)
    add    ax,5                    ; To round the second decimal place 
                                   ; (i.e. 3.996 GHz become 4.00 GHz)

;-------------------------------------------------------------------------------
; Put Decimal Frequency Value in DX    
;-------------------------------------------------------------------------------
    mov    cx,1000
    xor    dx,dx                   ; MUST CLEAR DX before of the division!
    div    cx                      ; After this, DX will have the decimal part from frequency 
    

;-------------------------------------------------------------------------------
; Convert the GHz Unity (AX) to ASCII and Store on Message Buffer   
;-------------------------------------------------------------------------------
    aam    0Ah                     ; Frequency unity value to BCD (0Ah = Decimal)
    or     ax,3030h                ; BCD to ASCII
    mov    di,CPU_FREQ
    cld                            ; Ensures which DI will be incremented after STOSB/STOSW
    stosb                          ; Store the frequency integer value on the phrase buffer
    

;-------------------------------------------------------------------------------
; Convert GHz Decimal Value (DX) to 2 Decimal Places
; Note: DO NOT put it in 1000 division above (i.e. MOV CX,10000) because
;       that's it not works!
;-------------------------------------------------------------------------------
    mov    ax,dx                   ; Copy decimal value to AX
    mov    cx,10
    xor    dx,dx                   ; MUST CLEAR DX before of the division!
    div    cx                      ; will show 2 decimal places only
    

;-------------------------------------------------------------------------------
; Convert the GHz Decimal Places to ASCII and Store on Message Buffer   
;-------------------------------------------------------------------------------
    aam    0Ah                     ; Frequency fractional value to BCD (0Ah = Decimal)
    or     ax,3030h                ; BCD to ASCII
    xchg   ah,al
    inc    di                      ; Skip decimal dot
    stosw                          ; Store the 2 decimal places on the phrase buffer

    
;-------------------------------------------------------------------------------
; Show Processor Actual Frequency    
;-------------------------------------------------------------------------------
    mov    dx,CPU_FREQ_INFO
    mov    ah,09h
    int    21h


;-------------------------------------------------------------------------------
; Finish Successfully (Error Code 0)
;-------------------------------------------------------------------------------
    cmp    byte [DOS_VERSION],2    ; Check DOS version to execute proper exit interrupt
    jb     DOS_1_EXIT              ; Finish with the INT 20h (DOS 1.x)
    mov    ax,4C00h
    int    21h


;-------------------------------------------------------------------------------
; Unknown Processor or not Supported
;-------------------------------------------------------------------------------
Bad_Proc:
    mov    dx,NEED_PENTIUM_MSG
    mov    ah,09h
    int    21h
    cmp    byte [DOS_VERSION],2    ; Check DOS version to execute proper exit interrupt
    jb     DOS_1_EXIT              ; Finish with the INT 20h (DOS 1.x)
    mov    ax,4C01h
    int    21h                     ; Finish with error code 1


;-------------------------------------------------------------------------------
; Exit for DOS 1.x Only (MS-DOS 1.x not support INT 21h 0x4C exit function)
;-------------------------------------------------------------------------------
DOS_1_EXIT:
    int    20h                     ; For DOS 1.x


;-------------------------------------------------------------------------------
; Waits Clock Tick to Change (for Syncronism and Timing)
;
; Input : None
; Output: DX = Current Clock Tick value
;         AX, BX destroyed
;         DS preserved
;-------------------------------------------------------------------------------
Wait_Clock_Tick_Change:
    push   ds                      ; ALWAYS PRESERVE SEGMENT REGISTERS IF ALTERED
    mov    ax,0040h                ; Access BIOS Data Area (BDA)
    mov    ds,ax
    mov    bx,[006Ch]              ; Get Low word of intitial tick value

.Wait_New_Tick:
    mov    dx,[006Ch]              ; Get Low word of tick count
    cmp    dx,bx
    je     .Wait_New_Tick
    pop    ds                      ; ALWAYS RESTORE SEGMENT REGISTERS IF ALTERED
    ret


;-------------------------------------------------------------------------------
; Store DOS Version for Support Checking of INT 21h 0x4C Function
;-------------------------------------------------------------------------------
DOS_VERSION        db 0


;-------------------------------------------------------------------------------
; APERF Support Flag
;-------------------------------------------------------------------------------
CPU_HAS_APERF      db 0            ; Flag for IA32_APERF MSR support (1 = has APERF)


;-------------------------------------------------------------------------------
; Messages
;-------------------------------------------------------------------------------
NEED_PENTIUM_MSG   db 0Dh, 0Ah, "Requires a Pentium or newer processor.", 0Dh, 0Ah, "$"
WINDOWS_E_MODE_MSG db 0Dh, 0Ah, "Can not read the processor frequency in Windows Enhanced Mode!", 0Dh, 0Ah, "$"
INVARIANT_TSC_MSG  db 0Dh, 0Ah, "Processor has an Invariant TSC!", "$"
TSC_READING_MSG    db 0Dh, 0Ah, "Reading the CPU frequency through of TSC register...$"
APERF_READING_MSG  db 0Dh, 0Ah, "Reading the CPU frequency through of IA32_APERF MSR...$"
CPU_FREQ_INFO      db 0Dh,      "The current CPU clock speed is "
CPU_FREQ           db " .   GHz.              ", 0Dh, 0Ah, "$"


SIGNATURE          db "CPUFREQ 4 24JUN2026"
