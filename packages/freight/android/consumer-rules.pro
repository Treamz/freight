# Shipped with the plugin so consuming apps do not have to discover this.
#
# The Play Asset Delivery Kotlin extensions reference an annotation from Play
# Services that is not on the classpath, and R8 treats the missing class as an
# error in release builds. It is only an annotation — nothing resolves it at
# runtime — so warning about it is noise that fails the build.
-dontwarn com.google.android.gms.common.annotation.NoNullnessRewrite
