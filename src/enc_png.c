/**
 * @file
 * @brief This program writes PNG stream to memory.
 * @author Stephen Gilbert
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <png.h>

typedef int g2int; /**< Long integer type. */ 

/**
 * location to write PNG stream
*/

struct png_stream {

   unsigned char *stream_ptr;
/*
**  number of bytes written
*/
   g2int stream_len;
};
typedef struct png_stream png_stream; /**< location to write PNG stream. */

/**
 * Custom write function used to that libpng will write to memory
 * location instead of a file on disk.
 *
 * @param png_ptr pointer
 * @param data data
 * @param length length
 *
 * @author Stephen Gilbert
*/

static void
user_write_data(png_structp png_ptr,png_bytep data, png_uint_32 length)
{
     unsigned char *ptr;
     g2int offset;
     png_stream *mem;

     mem = (png_stream *)png_get_io_ptr(png_ptr);
     ptr = mem->stream_ptr;
     offset = mem->stream_len;
     memcpy(ptr + offset, data, length);
     mem->stream_len += length;
}

/**
 * Dummy Custom flush function.
 *
 * @param png_ptr Pointer to PNG struct.
 *
 * @author Stephen Gilbert
*/

static void 
user_flush_data(png_structp png_ptr)
{
}

/**
 * create png_structs to write png stream into memory.
 *
 * @param data data.
 * @param width width.
 * @param height height.
 * @param nbits number of bits.
 * @param pngbuf PNG buffer.
 * @return pnglen the length of png stream
 *
 * @author Stephen Gilbert
*/
int 
enc_png(char *data, g2int *width, g2int *height, g2int *nbits, char *pngbuf)
{
 
    int color_type;
    g2int j, bytes, pnglen, bit_depth;
    png_structp png_ptr;
    png_infop info_ptr;
    png_bytep **row_pointers;
    png_stream write_io_ptr;

    /* create and initialize png_structs. */
    png_ptr = png_create_write_struct(PNG_LIBPNG_VER_STRING, (png_voidp)NULL, 
                                      NULL, NULL);
    if (!png_ptr)
       return -1;

    info_ptr = png_create_info_struct(png_ptr);
    if (!info_ptr)
    {
       png_destroy_write_struct(&png_ptr,(png_infopp)NULL);
       return -2;
    }

    /* Set Error callback. */
    if (setjmp(png_jmpbuf(png_ptr)))
    {
       png_destroy_write_struct(&png_ptr, &info_ptr);
       return -3;
    }

    /* Initialize info for writing PNG stream to memory. */
    write_io_ptr.stream_ptr = (png_voidp)pngbuf;
    write_io_ptr.stream_len = 0;

    /* Set new custom write functions. */
    png_set_write_fn(png_ptr, (png_voidp)&write_io_ptr, (png_rw_ptr)user_write_data,
                    (png_flush_ptr)user_flush_data);

    /* Set the image size, colortype, filter type, etc... */
    bit_depth = *nbits;
    color_type = PNG_COLOR_TYPE_GRAY;
    if (*nbits == 24) 
    {
        bit_depth = 8;
        color_type = PNG_COLOR_TYPE_RGB;
    }
    else if (*nbits == 32) 
    {
        bit_depth = 8;
        color_type = PNG_COLOR_TYPE_RGB_ALPHA;
    }
    png_set_IHDR(png_ptr, info_ptr, *width, *height,
       bit_depth, color_type, PNG_INTERLACE_NONE,
       PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);

    /* Put image data into the PNG info structure. */
    bytes = *nbits / 8;
    row_pointers = malloc((*height) * sizeof(png_bytep));
    for (j = 0; j < *height; j++) 
        row_pointers[j] = (png_bytep *)(data+(j * (*width) * bytes));
    png_set_rows(png_ptr, info_ptr, (png_bytepp)row_pointers);

    /* Do the PNG encoding, and write out PNG stream. */
    png_write_png(png_ptr, info_ptr, PNG_TRANSFORM_IDENTITY, NULL);

    /* Clean up. */
    png_destroy_write_struct(&png_ptr, &info_ptr);
    free(row_pointers);
    pnglen = write_io_ptr.stream_len;
    return pnglen;

}

