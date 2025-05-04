/*
	EDITED VERSION OF

	ガウシアンフィルタとSobel シェーダー2 by あるる（きのもと 結衣）
	Sobel with Gaussian filter Shader2 by @arlez80

	MIT License
*/

shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform float alpha : hint_range( 0.0, 1.0 ) = 1.0;

vec3 gaussian5x5( sampler2D tex, vec2 uv, vec2 pix_size )
{
	vec3 p = vec3( 0.0, 0.0, 0.0 );

	float coef[9] = {
	0.0625, 0.09375, 0.0625,
	0.09375, 0.140625, 0.09375,
	0.0625, 0.09375, 0.0625};

	for( int y=-1; y<=1; y++ ) {
		for( int x=-1; x<=1; x ++ ) {
			p += ( texture( tex, uv + vec2( float( x ), float( y ) ) * pix_size ).rgb ) * coef[(y+1)*3 + (x+1)];
		}
	}
	return p;
}
	// ガウシアンフィルタ

void fragment( )
{
	vec3 pix[9]; // 3 x 3
	for( int y=0; y<3; y ++ ) {
		for( int x=0; x<3; x ++ ) {
			pix[y*3+x] = gaussian5x5( TEXTURE, UV + vec2( float( x-1 ), float( y-1 ) ) * TEXTURE_PIXEL_SIZE, TEXTURE_PIXEL_SIZE );
		}
	}

	// Sobelフィルタ
	vec3 sobel_src_x = (
		pix[0] * -1.0
	+	pix[3] * -2.0
	+	pix[6] * -1.0
	+	pix[2] * 1.0
	+	pix[5] * 2.0
	+	pix[8] * 1.0
	);
	vec3 sobel_src_y = (
		pix[0] * -1.0
	+	pix[1] * -2.0
	+	pix[2] * -1.0
	+	pix[6] * 1.0
	+	pix[7] * 2.0
	+	pix[8] * 1.0
	);

	float x = sobel_src_x.r + sobel_src_x.g + sobel_src_x.b;
	float y = sobel_src_y.r + sobel_src_y.g + sobel_src_y.b;
	COLOR = vec4( vec3( x * 2. + 0.5, y * 2. + 0.5, 0 ), alpha );
}