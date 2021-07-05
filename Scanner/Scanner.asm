#make_bin#

#LOAD_SEGMENT=FFFFh#
#LOAD_OFFSET=0000h#

#CS=0000h#
#IP=0000h#

#DS=0000h#
#ES=0000h#

#SS=0000h#
#SP=FFFEh#

#AX=0000h#
#BX=0000h#
#CX=0000h#
#DX=0000h#
#SI=0000h#
#DI=0000h#
#BP=0000h#

; add your code here
SMOTOR1          EQU    88H     
SMOTOR2          EQU    8AH     
MUX_ADC         EQU    84H      
ADCD                   EQU    80H      
SIGNAL_ADC    EQU   8CH     




        jmp     st1 
        ;jmp st1 - takes 3 bytes followed by nop that is 4 bytes
                nop  
        ;int 1 is not used so 1 x4 = 00004h - it is stored with 0
                dw      0000
                dw      0000   
        ;eoc - is used as nmi - ip value points to ad_isr and cs value will
        ;remain at 0000
                dw      ad_isr
                dw      0000
        ;int 3 to int 255 unused so ip and cs intialized to 0000
        ;from 3x4 = 0000cH		 
                db     1012 dup(0)
        ;main program        
        IM_BUFFER       DB      40901 DUP(0) 
                        DB      40000 DUP(0)     
POS1                    DB      33H           ;position of stepper motor 1
POS2                    DB      33H           ;position of stepper motor 2
                
    st1:      cli 
        ; intialize ds, es,ss to start of RAM
                mov       ax,0200h
                mov       ds,ax
                mov       es,ax
                mov       ss,ax
                mov       sp,0FFFEH
                mov       si,0000 
                
                

        ; MOV AL, 36H             ;initializing counter 0 of 8254 (not in proteus)
        ; OUT 96H, AL
        ; MOV AL, 0005H           ; giving a count of 5d to counter to get a 1mhz signal
        ; OUT 90H, AL
        ; MOV AL, 0000H
        ; OUT 90H, AL

        MOV AL,9AH         ;control word to initialize 8255A(1)     
        OUT 86H,AL


        MOV AL,81H         ;control word to initialize 8255A(2)     
        OUT 8EH,AL

        MOV CX,801                  ; row movement counter         
        MOV SI,OFFSET IM_BUFFER     ; image storage area      
        
    POLL:   IN AL, SIGNAL_ADC
        AND AL, 01H
        JZ  POLL
        CALL DEBOUNCE
      


    NEXTROW:       PUSH CX
            MOV DL,0
            MOV CX,8    
            MOV BX,0  


    READAGAIN1: CALL READPIX
        MOV AL,POS1
        ROR AL,1                      ; rotates motor through one step
        OUT SMOTOR1,AL
        CALL DELAY_MOT
        MOV POS1,AL
        INC DL
        LOOP READAGAIN1
	INC BX
        ;0.5cm of row has been read. 
        ;Whole assembly is to be moved by 0.4125 cm to read next 5 bytes of data or 40 pixels

        MOV CX,33               ; 0.4125/0.0125
        MOV AL,POS1
	CMP BX, 20            ;a loop of 20 to read the entire row except one last pixel
        JZ DONE

    AGAIN1:            ROR AL,1
        OUT SMOTOR1,AL
        CALL DELAY_MOT
        LOOP AGAIN1

        MOV POS1,AL  

        ;now the next 0.5cm of the row has to be read

        ADD SI,5
        MOV DL,0
        MOV CX,8
	JMP READAGAIN1
        
DONE:        

        ;Whole row has been read
        ;Only the last pixel is to be read
        ;reading the last pixel

        MOV AL,POS1
        ROR AL,1
        OUT SMOTOR1,AL
        CALL DELAY_MOT
        MOV POS1,AL

        MOV DI, 1                        ;Checking if NMI is there

        MOV AL,90H                  ;enable ALE(ALE = 1)       
        OUT SIGNAL_ADC,AL

        MOV AL,04H                  ;enable the last photodiode         
        OUT MUX_ADC,AL

        MOV AL,50H                  ;start pulse            
        OUT SIGNAL_ADC,AL                     

        ;provide a delay of 2 microsecs to the start signal

        NOP
        NOP
        NOP
        NOP

        MOV AL,10h                                            
        OUT SIGNAL_ADC,AL

        x2: CMP DI, 0
            JNZ x2                          ;wait for interrupt



        MOV CX,760            ;bring the horizontal motor back to starting position
        MOV AL,POS1
    AGAIN2:            ROL AL,1
        OUT SMOTOR1,AL
        CALL DELAY_MOT
        LOOP AGAIN2
        MOV POS1,AL     

        MOV AL,POS2                         ;move verticle motor downwards by 1 step
        ROR AL,1
        OUT SMOTOR2,AL

        CALL DELAY_MOT
        MOV POS2,AL                  ;updating position of vertical motor
        ADD SI,6
        POP CX
        LOOP NEXTROW                    ; start the program to read the next row  
       
        MOV AL, 00H
        OUT SIGNAL_ADC, AL                  ; LIGHTING THE LED FOR DENOTING COMPLETION OF SCAN



READPIX     PROC     NEAR

        ;takes SI and DL as arguments
        PUSH BX                                             
        PUSH CX
        MOV DI, 1               ; for checking if NMI is there
        MOV BX,0         

        ;BX holds the diode being selected currently through the selection pins of ADC

        MOV CX,5

        NEXTBYTE:   MOV AL,90H           ; enable ALE                   
        OUT SIGNAL_ADC,AL

        MOV AL,BL                    ;select diode using BX             
        OUT MUX_ADC,AL

        MOV AL,50H                                                      
        OUT SIGNAL_ADC,AL ;start pulse

        ; delay of 2 microsecs
        NOP
        NOP
        NOP
        NOP


        MOV AL,10h                                        
        OUT SIGNAL_ADC,AL  ;make pulse 0

        x1: CMP DI, 0 
            JNZ x1                          ;wait for interrupt

        FORWARD:    INC BX                  ; next photodiode
        LOOP NEXTBYTE
        POP CX
        POP BX
RET

READPIX     ENDP


DELAY_MOT    PROC    NEAR

;procedure to provide 1 ms delay for movement of motor

        PUSH CX
        MOV CX,501

        X7:                    NOP
        LOOP X7
        POP CX
RET

DELAY_MOT   ENDP              

;Procedure for debounce delay
DEBOUNCE proc near

;delay calculation
;no. of cycles for loop = 18 if taken/ 5 if not taken = 14,999 x 18 + 5
;no. of cycles for ret 16
;no. of cycles for call 19
;no. of cycles for mov 4 
;clock speed 1 MHz - 1 clock cycle 1us (micro seconds)
;total no.cycles delay = clkcycles for call + mov cx,imm + (content of cx-1)*18+5 + ret= (19 + 4 + (18*14,999) + 5 + 16)* 1 us = 0.270026s
;adjusted for proteus, due to CPU load 
    
        mov     cx,15000
debloop1: loop  debloop1
    
	
        ret
        DEBOUNCE endp 

ad_isr:
    DEC di
    CMP BX, 20                  ; checking if its the end of row and we want read the last pixel only or not 
    JNZ REGULAR                 ; if no then we go to our regular sampling of all 5 diodes.
    MOV AL,30H                 ;output enable = 1       
    OUT SIGNAL_ADC,AL
    IN AL,ADCD                    ;AL contains output of ADC now
    CMP AL,00H                      ; checking if value is 0, if yes then skip the pixel(as already initialized 0)
    JZ S1
    OR [SI+5],80H                   ;else load 1 in the 5th photodiode's location 
    JZ S1
    REGULAR:    
    MOV AL,30H                          
    OUT SIGNAL_ADC,AL   ;OE = 1
    IN AL,ADCD                      ;AL contains ADC output now

    CMP AL,00H                  ; checking if value is 0, if yes then skip the pixel(as already initialized 0)
    JZ S1 
    MOV AL,80H
    PUSH CX
    MOV CL,DL
    SHR AL,CL                      ; shifting the 1 to the bit corresponding to which pixel is currently read in 0.1cm (as o.1cm contaisn 8 pixels) 
    POP CX
    OR [BX+SI],AL                 ;stores in memory (making the corresponding bit 1 for detection of pixel)
    S1:    
    IRET






