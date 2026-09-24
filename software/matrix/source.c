#include <stdio.h>
#include <string.h>
#include "system.h"
#include "io.h"
//#include "sys/alt_timestamp.h"
#include "alt_types.h"

// ---------------------------------------------------------------------------
// Register map — khớp với matrix_mult_avalon.v
// ---------------------------------------------------------------------------
/*#define BASE_ADDR       MATRIX_0_BASE
#define REG_A_BASE      0x00   // A[0..15] tại word-offset 0x00..0x0F
#define REG_B_BASE      0x10   // B[0..15] tại word-offset 0x10..0x1F
#define REG_CTRL        0x20   // bit[0] = start
#define REG_STATUS      0x21   // bit[0] = done
#define REG_C_BASE      0x30   // C[0..15] tại word-offset 0x30..0x3F

#define FPGA_TIMEOUT    20000000

// ---------------------------------------------------------------------------
// FP16 ↔ FP32 conversion (safe, no UB)
// ---------------------------------------------------------------------------
float fp16_to_fp32(unsigned short hp) {
    unsigned int sign = (hp >> 15) & 1;
    int          exp  = (hp >> 10) & 0x1F;
    unsigned int mant =  hp        & 0x3FF;
    unsigned int bits;

    if (exp == 0) {
        if (mant == 0) {
            bits = sign << 31;
        } else {
            exp = 1;
            while ((mant & 0x400) == 0) { mant <<= 1; exp--; }
            mant &= 0x3FF;
            bits = (sign << 31) | ((unsigned int)(exp - 15 + 127) << 23) | (mant << 13);
        }
    } else if (exp == 31) {
        bits = (sign << 31) | (0xFFu << 23) | (mant << 13);
    } else {
        bits = (sign << 31) | ((unsigned int)(exp - 15 + 127) << 23) | (mant << 13);
    }

    float f;
    memcpy(&f, &bits, sizeof(f));
    return f;
}

unsigned short fp32_to_fp16(float f) {
    unsigned int bits;
    memcpy(&bits, &f, sizeof(bits));

    unsigned int sign =  (bits >> 16) & 0x8000;
    int          exp  = ((bits >> 23) & 0xFF) - 127 + 15;
    unsigned int mant =   bits        & 0x7FFFFF;

    if (exp <= 0)  return (unsigned short)sign;
    if (exp >= 31) return (unsigned short)(sign | 0x7C00);
    return (unsigned short)(sign | ((unsigned int)exp << 10) | (mant >> 13));
}
*/

int main(void) {
 /*   printf("\n======================================================\n");
    printf("   SO SANH HIEU NANG: CPU NIOS II vs FPGA ACCELERATOR\n");
    printf("======================================================\n");

    if (alt_timestamp_start() < 0) {
        printf("[ERROR] Khong khoi dong duoc timer! Kiem tra Qsys co Interval Timer.\n");
        return 1;
    }

    // --- Ma trận mẫu: A = Diag(2.0), B = I ---
    const unsigned short FP16_ZERO = 0x0000;
    const unsigned short FP16_ONE  = 0x3C00;
    const unsigned short FP16_TWO  = 0x4000;

    unsigned short A[16], B[16], fpga_C[16], cpu_C[16];
    int i, r, c, k;

    for (i = 0; i < 16; i++) {
        A[i] = (i % 5 == 0) ? FP16_TWO : FP16_ZERO;
        B[i] = (i % 5 == 0) ? FP16_ONE : FP16_ZERO;
    }

    // ==========================================================
    // PHẦN 1: FPGA
    // ==========================================================
    printf("\n[FPGA] Nap du lieu ma tran A va B...\n");
    for (i = 0; i < 16; i++) {
        IOWR_32DIRECT(BASE_ADDR, (REG_A_BASE + i) * 4, (alt_u32)A[i]);
        IOWR_32DIRECT(BASE_ADDR, (REG_B_BASE + i) * 4, (alt_u32)B[i]);
    }

    printf("[FPGA] Bat dau tinh toan (start = 1)...\n");
    alt_u32 fpga_start = alt_timestamp();
    IOWR_32DIRECT(BASE_ADDR, REG_CTRL * 4, 1);

    while ((IORD_32DIRECT(BASE_ADDR, REG_STATUS * 4) & 0x01) == 0) {
            // Cho phan cung xu ly
    }

    alt_u32 fpga_end    = alt_timestamp();
    alt_u32 fpga_cycles = fpga_end - fpga_start;
    printf("[FPGA] Hoan tat! Doc ket qua...\n");

    for (i = 0; i < 16; i++) {
        fpga_C[i] = (unsigned short)(IORD_32DIRECT(BASE_ADDR, (REG_C_BASE + i) * 4) & 0xFFFF);
    }

    // ==========================================================
    // PHẦN 2: CPU SOFTWARE
    // ==========================================================
    printf("\n[CPU]  Tinh toan bang phan mem...\n");
    alt_u32 cpu_start = alt_timestamp();

    for (r = 0; r < 4; r++) {
        for (c = 0; c < 4; c++) {
            float sum = 0.0f;
            for (k = 0; k < 4; k++) {
                sum += fp16_to_fp32(A[r*4+k]) * fp16_to_fp32(B[k*4+c]);
            }
            cpu_C[r*4+c] = fp32_to_fp16(sum);
        }
    }

    alt_u32 cpu_end    = alt_timestamp();
    alt_u32 cpu_cycles = cpu_end - cpu_start;
    printf("[CPU]  Hoan tat!\n");

    // ==========================================================
    // PHẦN 3: SO SÁNH KẾT QUẢ
    // ==========================================================
    printf("\n%-8s | %-12s | %-12s | %s\n", "Vi tri", "FPGA (hex)", "CPU (hex)", "Ket qua");
    printf("---------|--------------|--------------|--------\n");

    int match = 0;
    for (i = 0; i < 16; i++) {
        int ok = (fpga_C[i] == cpu_C[i]);
        if (ok) match++;
        printf("C[%2d]   | 0x%04X       | 0x%04X       | %s\n",
               i, fpga_C[i], cpu_C[i], ok ? "OK" : "SACH LECH");
    }

    printf("\n=> %d/16 phan tu khop.\n", match);
    if (match == 16)
        printf("=> KET QUA: FPGA tinh dung hoan toan!\n");
    else
        printf("=> KET QUA: Co sai lech, kiem tra lai Verilog.\n");

    // ==========================================================
    // PHẦN 4: BÁO CÁO THỜI GIAN
    // ==========================================================
    printf("\n======================================================\n");
    printf("               BAO CAO THOI GIAN THUC THI\n");
    printf("======================================================\n");
    printf("FPGA : %lu chu ky\n", (unsigned long)fpga_cycles);
    printf("CPU  : %lu chu ky\n", (unsigned long)cpu_cycles);

    if (fpga_cycles > 0) {
        // Tránh dùng %f nếu BSP dùng reduced printf
        // Tính speedup * 100 rồi in dạng nguyên
        alt_u32 speedup_x100 = (alt_u32)((float)cpu_cycles / (float)fpga_cycles * 100.0f);
        printf("=> Speedup: %lu.%02lu lan\n",
               (unsigned long)(speedup_x100 / 100),
               (unsigned long)(speedup_x100 % 100));
    }*/

	printf("\n[CPU]  Tinh toan bang phan mem...\n");
    return 0;
}
