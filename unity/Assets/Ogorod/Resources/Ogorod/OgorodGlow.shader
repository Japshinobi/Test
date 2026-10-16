// Warm glow at sunrise and sunset, added with the "screen" blend.
Shader "Ogorod/Glow"
{
    Properties { _Color ("Glow colour", Color) = (0, 0, 0, 1) }
    SubShader
    {
        Tags { "Queue" = "Overlay+1" "RenderType" = "Transparent" "IgnoreProjector" = "True" }
        Pass
        {
            ZWrite Off ZTest Always Cull Off
            Blend OneMinusDstColor One
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            fixed4 _Color;
            float4 vert (float4 v : POSITION) : SV_POSITION { return UnityObjectToClipPos(v); }
            fixed4 frag () : SV_Target { return fixed4(_Color.rgb, 1); }
            ENDCG
        }
    }
}
